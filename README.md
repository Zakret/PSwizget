# PSwizget
PowerShell script that allow you to manage upgrade process with winget. 
It's adds a few more options than 'winget upgrade --all':
- create file with packages you would like to omit
- add or remove packages from toSkip file direcly from the script
- automaticaly omit packages with "unknown" installed version or when installed version and avaliable version does not match
- it tries to gues right installed version by reading pattern from avaliable version
- manually edit upgrade quene

This is my first powershell script for educational purposes.

![wizget_screenshot](https://user-images.githubusercontent.com/78523122/175819001-c0ecea78-fdad-4907-9388-e36f0a11d69b.jpg)
