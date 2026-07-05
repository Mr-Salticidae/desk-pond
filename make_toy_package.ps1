# 工位池塘 · B站 toy 上传包打包脚本
# 前置：已用 Godot 导出 Web 版到 build/web（godot --headless --path . --export-release Web build/web/index.html）
# 作用：B站 toy 托管会吞 .pck 扩展名的文件（上传后 404，报 "Failed loading file 'index.pck'"），
#       故把 pck 改名为 index.data（toy 实证放行的扩展名），并给 index.html 的 GODOT_CONFIG
#       加 mainPack 指向新文件名。产物 = promo/toy-release/desk-pond-toy.zip。
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$src = Join-Path $root "build\web"
$dst = Join-Path $root "build\web-toy"
$out = Join-Path $root "promo\toy-release\desk-pond-toy.zip"

if (-not (Test-Path (Join-Path $src "index.pck"))) { throw "先导出 Web 版到 build/web" }

Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $src $dst -Recurse
Remove-Item (Join-Path $dst "*.import") -ErrorAction SilentlyContinue
Rename-Item (Join-Path $dst "index.pck") "index.data"

$html = [System.IO.File]::ReadAllText((Join-Path $dst "index.html"))
$html = $html.Replace('"executable":"index",', '"executable":"index","mainPack":"index.data",')
$html = $html -replace '"fileSizes":\{"index\.pck":', '"fileSizes":{"index.data":'
if ($html -notmatch '"mainPack":"index\.data"') { throw "GODOT_CONFIG 补丁失败，检查导出模板的 index.html 结构是否变了" }
[System.IO.File]::WriteAllText((Join-Path $dst "index.html"), $html, (New-Object System.Text.UTF8Encoding $false))

New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
Compress-Archive -Path (Join-Path $dst "*") -DestinationPath $out -Force
"打包完成：$out（{0:N1} MB）" -f ((Get-Item $out).Length / 1MB)
