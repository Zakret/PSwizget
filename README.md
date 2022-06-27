# PSwizget
PowerShell script that allow you to manage the upgrade process with winget. 
It adds a few more options than 'winget upgrade --all':
- create a file with the packages you would like to omit
- add or remove packages from toSkip file directly from the script
- automatically omit packages with "unknown" installed version, or when the installed version and the available version does not match
- it tries to guess the correct installed version by reading the pattern from the available version
- manually edit the upgrade queue
- quick mode (it's similar to 'winget upgrade --all' but with a blacklist applied)

This is my first powershell script for educational purposes.

![PSwizget_preview](https://user-images.githubusercontent.com/78523122/176022113-95214442-96f6-4811-9184-b7eea3b71f65.jpg)
