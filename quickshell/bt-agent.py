#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════
# BT-AGENT — the Bluetooth panel's pairing agent, and the three link
# verbs whose failures the panel has to put into words.
#
# WHY THIS EXISTS AT ALL. Quickshell 0.3.1's Bluetooth module binds
# BlueZ well, but two things are missing from it (read in its source,
# src/bluetooth/device.cpp):
#
#   * NO AGENT. Pairing a phone or a keyboard is BlueZ calling an
#     org.bluez.Agent1 -- "does 482913 match?", "what is the PIN?" --
#     and nothing in the module can answer. Without one, only headphones
#     that ask nothing could ever pair.
#   * NO ERRORS. pair() and connect() write a failure to the log and
#     nothing else: no signal, no property. The panel could only say
#     "it didn't work", never "it's out of range" or "wrong code".
#
# So this process is an Agent1 and a caller of Pair / Connect /
# Disconnect / CancelPairing, and it tells the panel what happened.
# Everything else -- the device list, power, trust, forget, discovery --
# stays the module's, bound directly.
#
# ── NO LIBRARIES, ON PURPOSE ────────────────────────────────────
# dbus-python and PyGObject are not on every machine, and a panel that
# can list devices but not pair them because a Python package is
# missing fails in the least legible way possible. The D-Bus wire format
# is small and stable (the spec is two pages for what an agent needs),
# so this speaks it over the socket itself: python3's standard library
# and nothing else, which the Search panel's apps.py already needs.
#
# ── THE AGENT IS OURS ONLY FOR OUR OWN CALLS ────────────────────
# It is registered but never asks to be the DEFAULT agent. BlueZ routes
# a pairing to the agent of the connection that called Pair, so every
# pairing started from the panel lands here, and a desktop that has its
# own agent (GNOME, bluedevil) keeps it for everything else.
#
# ── PROTOCOL — one line each way ────────────────────────────────
# stdin:   pair <device path>        connect <device path>
#          disconnect <device path>  cancelpair <device path>
#          yes | no | value <text>   (answers the prompt that is open)
# stdout:  JSON, one object a line:
#   {"ev":"ready"}                              registered, listening
#   {"ev":"ask","path":P,"kind":"confirm","code":"482913"}
#   {"ev":"ask","path":P,"kind":"allow"}        pair with no number
#   {"ev":"ask","path":P,"kind":"pin"}          free text, up to 16
#   {"ev":"ask","path":P,"kind":"passkey"}      digits, up to 999999
#   {"ev":"show","path":P,"code":"309614","entered":2}   type it there
#   {"ev":"withdrawn"}                          BlueZ took its question back
#   {"ev":"done","verb":V,"path":P,"ok":true}
#   {"ev":"done","verb":V,"path":P,"ok":false,"error":"AuthenticationFailed","message":"…"}
#   {"ev":"fatal","message":"…"}                then exit 1
#
# It exits when stdin closes. The panel runs it behind `setpriv
# --pdeathsig TERM`, so it also dies with the shell; BlueZ drops the
# agent, and cancels any pairing it was carrying, when the socket closes.
# ═══════════════════════════════════════════════════════════════

import json
import os
import selectors
import socket
import struct
import sys

AGENT_PATH = "/org/datum/bluetooth/agent"
CAPABILITY = "KeyboardDisplay"   # shows a code AND takes one: every pairing kind has a screen

# ── THE WIRE FORMAT ──────────────────────────────────────────────
# Enough of the D-Bus marshalling spec for what an agent sends and
# receives: basic types, strings, arrays, structs, dict entries and
# variants. A variant is written from a (signature, value) pair and read
# back as its bare value.

ALIGN = {"y": 1, "b": 4, "n": 2, "q": 2, "i": 4, "u": 4, "x": 8, "t": 8, "d": 8,
         "h": 4, "s": 4, "o": 4, "g": 1, "v": 1, "a": 4, "(": 8, "{": 8}
FIXED = {"y": "B", "b": "I", "n": "h", "q": "H", "i": "i", "u": "I", "x": "q", "t": "Q",
         "d": "d", "h": "I"}


def pad(n, a):
    return (-n) % a


def next_type(sig, i):
    """Index just past the complete type that starts at sig[i]."""
    c = sig[i]
    if c == "a":
        return next_type(sig, i + 1)
    if c in "({":
        close = ")" if c == "(" else "}"
        i += 1
        while sig[i] != close:
            i = next_type(sig, i)
        return i + 1
    return i + 1


def split_sig(sig):
    out, i = [], 0
    while i < len(sig):
        j = next_type(sig, i)
        out.append(sig[i:j])
        i = j
    return out


def put(buf, t, v, e):
    c = t[0]
    buf.extend(b"\0" * pad(len(buf), ALIGN[c]))
    if c in FIXED:
        buf.extend(struct.pack(e + FIXED[c], v))
    elif c in "so":
        b = v.encode()
        buf.extend(struct.pack(e + "I", len(b)) + b + b"\0")
    elif c == "g":
        b = v.encode()
        buf.extend(bytes([len(b)]) + b + b"\0")
    elif c == "v":
        put(buf, "g", v[0], e)
        put(buf, v[0], v[1], e)
    elif c == "a":
        et = t[1:]
        at = len(buf)
        buf.extend(b"\0\0\0\0")
        buf.extend(b"\0" * pad(len(buf), ALIGN[et[0]]))
        start = len(buf)
        for item in (v.items() if et[0] == "{" else v):
            put(buf, et, item, e)
        struct.pack_into(e + "I", buf, at, len(buf) - start)
    else:  # struct or dict entry
        for sub, val in zip(split_sig(t[1:-1]), v):
            put(buf, sub, val, e)


def get(buf, pos, t, e):
    c = t[0]
    pos += pad(pos, ALIGN[c])
    if c in FIXED:
        f = e + FIXED[c]
        return struct.unpack_from(f, buf, pos)[0], pos + struct.calcsize(f)
    if c in "so":
        n = struct.unpack_from(e + "I", buf, pos)[0]
        return bytes(buf[pos + 4:pos + 4 + n]).decode("utf-8", "replace"), pos + 5 + n
    if c == "g":
        n = buf[pos]
        return bytes(buf[pos + 1:pos + 1 + n]).decode(), pos + 2 + n
    if c == "v":
        sig, pos = get(buf, pos, "g", e)
        return get(buf, pos, sig, e)
    if c == "a":
        n = struct.unpack_from(e + "I", buf, pos)[0]
        et = t[1:]
        pos += 4
        pos += pad(pos, ALIGN[et[0]])
        end, out = pos + n, []
        while pos < end:
            item, pos = get(buf, pos, et, e)
            out.append(item)
        return (dict(out) if et[0] == "{" else out), end
    out = []
    for sub in split_sig(t[1:-1]):
        item, pos = get(buf, pos, sub, e)
        out.append(item)
    return out, pos


CALL, RETURN, ERROR, SIGNAL = 1, 2, 3, 4
F_PATH, F_IFACE, F_MEMBER, F_ERROR, F_REPLY, F_DEST, F_SENDER, F_SIG = 1, 2, 3, 4, 5, 6, 7, 8


class Bus:
    def __init__(self):
        self.sock = self.connect(os.environ.get(
            "DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/var/run/dbus/system_bus_socket"))
        self.serial = 0
        self.inbox = bytearray()
        self.sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
        line = self.auth_line()
        if not line.startswith(b"OK"):
            raise OSError("the system bus refused us: " + line.decode(errors="replace"))
        self.sock.sendall(b"BEGIN\r\n")

    @staticmethod
    def connect(address):
        # An address is `;`-separated alternatives; only unix sockets are
        # a system bus in practice.
        last = OSError("no usable address in " + address)
        for alt in address.split(";"):
            kind, _, rest = alt.partition(":")
            if kind != "unix":
                continue
            keys = dict(kv.split("=", 1) for kv in rest.split(",") if "=" in kv)
            path = keys.get("path") or ("\0" + keys["abstract"] if "abstract" in keys else None)
            if path is None:
                continue
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect(path)
                return s
            except OSError as err:
                s.close()
                last = err
        raise last

    def auth_line(self):
        data = b""
        while not data.endswith(b"\r\n"):
            chunk = self.sock.recv(1)
            if not chunk:
                raise OSError("the system bus closed during authentication")
            data += chunk
        return data

    def send(self, kind, fields, sig="", args=(), flags=0):
        self.serial += 1
        body = bytearray()
        for t, v in zip(split_sig(sig), args):
            put(body, t, v, "<")
        if sig:
            fields[F_SIG] = ("g", sig)
        head = bytearray(b"l" + bytes([kind, flags, 1]) + struct.pack("<II", len(body), self.serial))
        put(head, "a(yv)", sorted(fields.items()), "<")
        head.extend(b"\0" * pad(len(head), 8))
        self.sock.sendall(bytes(head + body))
        return self.serial

    def call(self, dest, path, iface, member, sig="", args=()):
        return self.send(CALL, {F_PATH: ("o", path), F_IFACE: ("s", iface),
                                F_MEMBER: ("s", member), F_DEST: ("s", dest)}, sig, args)

    def reply(self, msg, sig="", args=()):
        self.send(RETURN, {F_REPLY: ("u", msg["serial"]), F_DEST: ("s", msg["sender"])},
                  sig, args, flags=1)

    def error(self, msg, name, text=""):
        self.send(ERROR, {F_REPLY: ("u", msg["serial"]), F_DEST: ("s", msg["sender"]),
                          F_ERROR: ("s", name)}, "s", [text], flags=1)

    def read(self):
        """Whatever complete messages the socket has. [] and None = closed."""
        chunk = self.sock.recv(65536)
        if not chunk:
            return None
        self.inbox.extend(chunk)
        out = []
        while len(self.inbox) >= 16:
            e = "<" if self.inbox[0:1] == b"l" else ">"
            body_len, serial, fields_len = struct.unpack_from(e + "III", self.inbox, 4)
            head_end = 16 + fields_len + pad(16 + fields_len, 8)
            if len(self.inbox) < head_end + body_len:
                break
            fields, _ = get(self.inbox, 12, "a(yv)", e)
            f = dict((code, val) for code, val in fields)
            body = self.inbox[head_end:head_end + body_len]
            args, pos = [], 0
            for t in split_sig(f.get(F_SIG, "")):
                v, pos = get(body, pos, t, e)
                args.append(v)
            out.append({"type": self.inbox[1], "serial": serial, "path": f.get(F_PATH, ""),
                        "iface": f.get(F_IFACE, ""), "member": f.get(F_MEMBER, ""),
                        "error": f.get(F_ERROR, ""), "reply": f.get(F_REPLY, 0),
                        "sender": f.get(F_SENDER, ""), "args": args})
            del self.inbox[:head_end + body_len]
        return out


# ── THE AGENT ────────────────────────────────────────────────────

def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


class Agent:
    def __init__(self, bus):
        self.bus = bus
        self.calls = {}      # our serial -> (verb, device path)
        self.prompt = None   # (BlueZ's call, kind) while a question is on screen

    def start(self):
        hello = self.bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                              "org.freedesktop.DBus", "Hello")
        register = self.bus.call("org.bluez", "/org/bluez", "org.bluez.AgentManager1",
                                 "RegisterAgent", "os", [AGENT_PATH, CAPABILITY])
        self.calls[hello] = ("hello", "")
        self.calls[register] = ("register", "")

    def command(self, line):
        verb, _, rest = line.strip().partition(" ")
        member = {"pair": "Pair", "connect": "Connect", "disconnect": "Disconnect",
                  "cancelpair": "CancelPairing"}.get(verb)
        if member and rest.startswith("/"):
            serial = self.bus.call("org.bluez", rest, "org.bluez.Device1", member)
            self.calls[serial] = (verb, rest)
        elif verb in ("yes", "no", "value") and self.prompt:
            call, kind = self.prompt
            self.prompt = None
            if verb == "no":
                self.bus.error(call, "org.bluez.Error.Rejected", "declined")
            elif kind == "pin" and verb == "value" and 0 < len(rest) <= 16:
                self.bus.reply(call, "s", [rest])
            elif kind == "passkey" and verb == "value" and rest.isdigit() and int(rest) <= 999999:
                self.bus.reply(call, "u", [int(rest)])
            elif kind in ("confirm", "allow") and verb == "yes":
                self.bus.reply(call)
            else:
                self.bus.error(call, "org.bluez.Error.Rejected", "unusable answer")

    def message(self, m):
        if m["type"] in (RETURN, ERROR) and m["reply"] in self.calls:
            verb, path = self.calls.pop(m["reply"])
            ok = m["type"] == RETURN
            if verb in ("hello", "register"):
                if not ok:
                    emit({"ev": "fatal", "message": (m["args"] or [m["error"]])[0]})
                    raise SystemExit(1)
                if verb == "register":
                    emit({"ev": "ready"})
                return
            out = {"ev": "done", "verb": verb, "path": path, "ok": ok}
            if not ok:
                out["error"] = m["error"].rsplit(".", 1)[-1]
                out["message"] = m["args"][0] if m["args"] and isinstance(m["args"][0], str) else ""
            emit(out)
            return
        if m["type"] != CALL:
            return
        name, a = m["member"], m["args"]
        if m["iface"] == "org.freedesktop.DBus.Introspectable":
            self.bus.reply(m, "s", ['<node><interface name="org.bluez.Agent1"/></node>'])
        elif m["path"] != AGENT_PATH or m["iface"] not in ("org.bluez.Agent1", ""):
            self.bus.error(m, "org.freedesktop.DBus.Error.UnknownMethod", name)
        elif name in ("RequestConfirmation", "RequestAuthorization", "RequestPinCode", "RequestPasskey"):
            kind = {"RequestConfirmation": "confirm", "RequestAuthorization": "allow",
                    "RequestPinCode": "pin", "RequestPasskey": "passkey"}[name]
            if self.prompt:   # one question at a time; the old one is moot
                self.bus.error(self.prompt[0], "org.bluez.Error.Canceled", "superseded")
            self.prompt = (m, kind)
            ev = {"ev": "ask", "path": a[0], "kind": kind}
            if kind == "confirm":
                ev["code"] = "%06d" % a[1]
            emit(ev)
        elif name == "DisplayPasskey":
            self.bus.reply(m)
            emit({"ev": "show", "path": a[0], "code": "%06d" % a[1], "entered": a[2]})
        elif name == "DisplayPinCode":
            self.bus.reply(m)
            emit({"ev": "show", "path": a[0], "code": a[1], "entered": -1})
        elif name == "AuthorizeService":
            # A profile on a device being paired from here, or one already
            # trusted: the person decided when they pressed Pair.
            self.bus.reply(m)
        elif name == "Cancel":
            self.prompt = None
            self.bus.reply(m)
            emit({"ev": "withdrawn"})
        elif name == "Release":
            self.bus.reply(m)
        else:
            self.bus.error(m, "org.freedesktop.DBus.Error.UnknownMethod", name)


def main():
    try:
        bus = Bus()
    except OSError as err:
        emit({"ev": "fatal", "message": str(err)})
        return 1
    agent = Agent(bus)
    agent.start()

    sel = selectors.DefaultSelector()
    sel.register(bus.sock, selectors.EVENT_READ, "bus")
    sel.register(sys.stdin.fileno(), selectors.EVENT_READ, "stdin")
    pending = b""
    while True:
        for key, _ in sel.select():
            if key.data == "bus":
                msgs = bus.read()
                if msgs is None:
                    emit({"ev": "fatal", "message": "the system bus went away"})
                    return 1
                for m in msgs:
                    agent.message(m)
            else:
                chunk = os.read(key.fd, 4096)
                if not chunk:
                    return 0
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    agent.command(line.decode("utf-8", "replace"))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
