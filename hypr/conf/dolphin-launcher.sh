# ~/.config/torbik/settings/filemanager.sh
#!/bin/bash
if pgrep -x dolphin > /dev/null; then
    dolphin
else
    dolphin --daemon && dolphin
fi
