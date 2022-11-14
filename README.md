# PSwizget
PowerShell script that allow you to manage the upgrade process with winget. 
It adds a few more options than 'winget upgrade --all':
- create a file with the packages you would like to omit;
- add or remove packages from the blacklist file directly from the script;
- automatically omit packages with "unknown" installed version, or when the formats of the installed version and the available version formats does not match;
- it tries to guess the correct installed version by reading the pattern from the available version;
- manually edit the upgrade queue;
- quick mode (it's similar to 'winget upgrade --all' but with a blacklist applied);
- wingetParam <string> option with custom parameters to pass to winget. '-h' is set by default;
- you can preselect one of the options available from the menu by adding the -option parameter with A, C or S argument.

This is my first powershell script for educational purposes.

Known issue with Windows Powershell ver. <= 5.1 (desktop):
Due to the ascii encoding, packages with longer names than 30 chars may corrupt the 'winget upgrade' result, i.e. info about the long name package and the packages listed after it. 
Please use this script with PowerShell ver. > 5.1 (core) if you can or avoid installing long name packages with winget.

![PSwizget_preview](https://user-images.githubusercontent.com/78523122/176022113-95214442-96f6-4811-9184-b7eea3b71f65.jpg)
