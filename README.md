# PSwizget
PowerShell script that allow you to manage the upgrade process with winget. 
It adds a few more options than 'winget upgrade --all':
- create a file with the packages you would like to omit
- add or remove packages from toSkip file directly from the script
- automatically omit packages with "unknown" installed version, or when the installed version and the available version does not match
- it tries to guess the correct installed version by reading the pattern from the available version
- manually edit the upgrade queue
- quick mode (it's similar to 'winget upgrade --all' but witha blacklist applied)

This is my first powershell script for educational purposes.

![wizget_screenshot](https://user-images.githubusercontent.com/78523122/175819001-c0ecea78-fdad-4907-9388-e36f0a11d69b.jpg)
