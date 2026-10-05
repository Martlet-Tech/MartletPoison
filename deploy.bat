@echo off
rem MartletPoison 部署脚本: 把仓库里的插件文件复制到游戏目录
set DEST=F:\Blizzard\Wow-Turtle\twmoa_1181_cn\twmoa_1181\Interface\AddOns\MartletPoison

copy /Y "%~dp0MartletPoison.toc"  "%DEST%\"
copy /Y "%~dp0MartletPoison.lua"  "%DEST%\"
copy /Y "%~dp0Bindings.xml"       "%DEST%\"
copy /Y "%~dp0README.md"          "%DEST%\"

echo.
echo 部署完成: %DEST%
echo 游戏内 小退重登 (或 /reload) 生效
pause
