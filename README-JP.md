# WSL2 ディスク容量最適化ツール

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/ja-jp/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/ja-jp/windows)
[![WSL2](https://img.shields.io/badge/WSL2-Compatible-green.svg)](https://docs.microsoft.com/ja-jp/windows/wsl/)

Windows 上で WSL2 と Docker Desktop の VHDX ファイルを安全に圧縮し、ホスト側のディスク容量を回収するためのツールです。

## このツールが解決する問題

WSL2 は各 Linux ディストリビューションを `ext4.vhdx` という仮想ディスクに保存します。このファイルは、パッケージキャッシュ、ビルド成果物、Docker イメージ、コンテナなどによって時間とともに肥大化します。

WSL2 内でファイルを削除しても、Windows 側の `ext4.vhdx` のサイズがすぐ小さくなるとは限りません。Linux ファイルシステム内では空き領域が増えていても、Windows ホスト側のファイルサイズは大きいまま残ることがあります。手動で `diskpart` による圧縮はできますが、VHDX が使用中のまま操作すると破損リスクがあり、手順ミスも起きやすいです。

## このツールが行うこと

WSL2 ディスク容量最適化ツールは、より安全な圧縮手順を自動化します。

- 標準的な WSL2 / Docker Desktop の場所から `ext4.vhdx` を検出します。
- 任意で、圧縮前に WSL 内で `docker system prune --force` を実行します。
- VHDX に触れる前に `wsl --shutdown` を実行し、マウント状態を解除します。
- 利用可能な場合は `Optimize-VHD`、利用できない場合は `diskpart` で VHDX を圧縮します。
- 実行前後のファイルサイズを表示し、Windows 側で回収できた容量を確認できるようにします。

## クイックスタート

**簡単 3 ステップ**で WSL2 のディスク容量を回収します。

1. 最新リリースをダウンロード、またはリポジトリをクローンします。
2. コマンドプロンプトまたは PowerShell を管理者として開きます。
3. `WSL2-DiskOptimizer.bat` を実行します。

```cmd
git clone https://github.com/kyto64/WSL2_Disk_Volume_Optimizer.git
cd WSL2_Disk_Volume_Optimizer
WSL2-DiskOptimizer.bat
```

> 重要: 大切な WSL ディストリビューションは、VHDX 圧縮前に必ずエクスポートまたはバックアップしてください。

## 必要条件

- WSL2 が有効な Windows 10/11
- PowerShell 5.1 以降
- 管理者権限
- Windows 標準の `diskpart`
- 任意: `Optimize-VHD` 用の Hyper-V PowerShell モジュール

## 使い方

### 対話型バッチラッパー

通常の手動実行ではこちらを使います。

```cmd
WSL2-DiskOptimizer.bat
```

このラッパーは管理者権限を確認し、`Optimize-WSL2Disk.ps1` が存在することを確認し、Docker cleanup の有無を確認してから PowerShell スクリプトを起動します。

Docker cleanup メニューでは以下を選べます。

- Docker cleanup をスキップ
- 既定の WSL ディストリビューションで `docker system prune --force` を実行
- 指定した WSL ディストリビューションで `docker system prune --force` を実行

この標準の Docker prune では、ボリュームや未使用のタグ付きイメージ全体は削除されません。

### PowerShell から直接実行

自分のスクリプトに組み込む場合はこちらを使います。

```powershell
.\Optimize-WSL2Disk.ps1
```

確認プロンプトを省略する場合:

```powershell
.\Optimize-WSL2Disk.ps1 -Force
```

WSL の停止と VHDX 圧縮前に Docker cleanup を実行する場合:

```powershell
.\Optimize-WSL2Disk.ps1 -DockerPrune
```

特定の WSL ディストリビューションで Docker cleanup を実行する場合:

```powershell
.\Optimize-WSL2Disk.ps1 -DockerPrune -DockerPruneDistro Ubuntu
```

## 実行結果の測定方法

回収できる容量は、作業内容、削除済みファイル、Docker の利用状況、ファイルシステムの状態、Windows 側のストレージ挙動によって変わります。固定の Before / After 数値ではなく、自分の環境で実測してください。

Windows 側で VHDX のファイルサイズを確認します。

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Packages\*\LocalState\ext4.vhdx" -Recurse -ErrorAction SilentlyContinue |
    Select-Object FullName, @{Name="SizeGB";Expression={[Math]::Round($_.Length / 1GB, 2)}}

Get-ChildItem "$env:LOCALAPPDATA\Docker" -Recurse -Filter "ext4.vhdx" -ErrorAction SilentlyContinue |
    Select-Object FullName, @{Name="SizeGB";Expression={[Math]::Round($_.Length / 1GB, 2)}}
```

WSL 内のファイルシステム使用量を確認します。

```bash
wsl -d Ubuntu -- df -h /
```

結果を共有する場合は、以下の環境情報も一緒に記録してください。

| 項目 | 例 |
|------|----|
| Windows バージョン | Windows 11 23H2 |
| WSL2 ディストリビューション | Ubuntu 22.04 |
| Docker Desktop | あり / なし |
| 実行前 VHDX サイズ | 実測値 |
| 実行後 VHDX サイズ | 実測値 |
| 回収できた容量 | 実測値から計算 |

## 実行ログ例

### 正常終了時

サイズとパスは環境によって変わります。

```text
[2026-05-31 14:30:00] [INFO] Starting WSL2 Disk Volume Optimizer
[2026-05-31 14:30:00] [INFO] Checking WSL status...
[2026-05-31 14:30:01] [INFO] Shutting down WSL...
[2026-05-31 14:30:04] [SUCCESS] WSL shutdown completed
[2026-05-31 14:30:04] [INFO] Searching for WSL VHD files...
[2026-05-31 14:30:05] [INFO] Found VHD files:
[2026-05-31 14:30:05] [INFO]   - C:\Users\user\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu_...\LocalState\ext4.vhdx (Size: <before> GB, Last Modified: ...)
[2026-05-31 14:30:05] [INFO] Optimizing VHD file: C:\Users\user\AppData\Local\Packages\...\ext4.vhdx
[2026-05-31 14:30:05] [WARN] Optimize-VHD is not available: ...
[2026-05-31 14:30:05] [INFO] Compressing VHD using diskpart: C:\Users\user\AppData\Local\Packages\...\ext4.vhdx
[2026-05-31 14:35:20] [SUCCESS] VHD compression completed using diskpart
[2026-05-31 14:35:20] [SUCCESS] Optimization completed: C:\Users\user\AppData\Local\Packages\...\ext4.vhdx
[2026-05-31 14:35:20] [INFO]   Before: <before> GB
[2026-05-31 14:35:20] [INFO]   After: <after> GB
[2026-05-31 14:35:20] [SUCCESS]   Space saved: <saved> GB
[2026-05-31 14:35:20] [INFO] Optimization process completed
[2026-05-31 14:35:20] [INFO] Success: 1 / 1 files
[2026-05-31 14:35:20] [SUCCESS] Please restart WSL to verify the results
```

### 管理者権限がない場合

```text
[ERROR] This script requires administrator privileges.

Please follow these steps:
1. Open Command Prompt or PowerShell as "Run as administrator"
2. Navigate to this folder
3. Run this batch file
```

### VHDX が見つからない場合

```text
[2026-05-31 14:30:00] [INFO] Starting WSL2 Disk Volume Optimizer
[2026-05-31 14:30:01] [SUCCESS] WSL shutdown completed
[2026-05-31 14:30:01] [INFO] Searching for WSL VHD files...
[2026-05-31 14:30:02] [ERROR] No VHD files found
```

## 安全性

VHDX 圧縮はディスク操作です。重要なディストリビューションに対して実行する前に、[docs/SAFETY.md](docs/SAFETY.md) を確認してください。

### 管理者権限が必要な理由

このスクリプトは `Optimize-VHD` または `diskpart` を使って VHDX を操作します。これらの処理では、仮想ディスクのアタッチ、確認、圧縮が行われるため、管理者権限が必要です。

### `wsl --shutdown` を実行する理由

圧縮前に `wsl --shutdown` を実行し、WSL ディストリビューションや Docker Desktop の WSL バックエンドが VHDX のファイルロックを解放するようにします。マウント中または使用中の VHDX を圧縮するのは危険です。

### バックアップ推奨

重要なディストリビューションは、実行前にエクスポートしてください。

```powershell
wsl --export Ubuntu D:\Backups\Ubuntu-before-vhdx-compact.tar
```

Docker Desktop の重要なイメージ、ボリューム、コンテナは Docker 側のバックアップ / エクスポート手順を使ってください。

## 処理フロー

1. 管理者権限を確認します。
2. WSL が利用可能か確認します。
3. `-Force` が指定されていない場合は確認プロンプトを表示します。
4. 任意で WSL 内の `docker system prune --force` を実行します。
5. `wsl --shutdown` を実行します。
6. 標準的な場所から `ext4.vhdx` を検索します。
7. `Optimize-VHD` または `diskpart` で VHDX を圧縮します。
8. 実行前後のサイズと成功件数を表示します。

## 既知の制限

- WSL1 ディストリビューションは対象外です。
- 現在の検索対象は `%LOCALAPPDATA%\Packages` と `%LOCALAPPDATA%\Docker` 配下の一般的なパスです。
- `wsl --import` などで作成したカスタム VHDX の場所は検出できない場合があります。
- Docker Desktop のバージョンによって VHDX の場所が異なる場合があります。
- ネットワークドライブ上の WSL インストールは対象外です。
- dry-run mode、JSON 出力、個別パス指定は未対応です。
- VHDX のサイズやディスク速度によって、圧縮に数分から数時間かかる場合があります。

## トラブルシューティング

| 問題 | 主な原因 | 対処 |
|------|----------|------|
| `Optimize-VHD is not available` | Hyper-V モジュールが利用できない | 想定内です。スクリプトは `diskpart` にフォールバックします |
| `This script must be run with administrator privileges` | 管理者権限で実行されていない | コマンドプロンプトまたは PowerShell を管理者として開き直します |
| `Docker system prune failed` | 選択した WSL ディストリビューションで Docker を利用できない | Docker を起動するか、Docker CLI が使える WSL ディストリビューションを選択します |
| `No VHD files found` | VHDX が標準以外の場所にある | カスタムパス対応は [docs/ROADMAP.md](docs/ROADMAP.md) を参照してください |
| WSL ディストリビューションが起動しない | VHDX 破損または中断されたディスク操作 | `wsl --export` で取得したバックアップから復元します |

診断コマンド:

```powershell
wsl --list --verbose
wsl -d <distribution> -- df -h /
```

## ドキュメント

- [Safety Guide](docs/SAFETY.md)
- [Roadmap](docs/ROADMAP.md)
- [English README](README.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Security Policy](SECURITY.md)

## サポート

- バグ報告や機能要望は GitHub Issues に投稿してください。
- ドキュメント、テスト、安全な自動化の改善 Pull Request を歓迎します。
- 問題報告時は Windows バージョン、WSL ディストリビューション、Docker Desktop の有無、実行コマンド、関連ログを含めてください。

## ライセンス

このプロジェクトは MIT License で配布されています。詳細は [LICENSE](LICENSE) を参照してください。

## 参考資料

- [Microsoft WSL ドキュメント](https://docs.microsoft.com/ja-jp/windows/wsl/)
- [PowerShell ドキュメント](https://docs.microsoft.com/ja-jp/powershell/)
- [元の解決方法リファレンス](https://qiita.com/siruku6/items/c91a40d460095013540d)

---

**重要**: VHDX を圧縮する前に、重要な WSL ディストリビューションをバックアップしてください。
