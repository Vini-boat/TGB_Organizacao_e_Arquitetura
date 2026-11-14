# Cria a VM "incus-host" (Alpine) no VirtualBox, sem administrador.
# Uso (PowerShell comum):  .\scripts\criar-vm.ps1 [-Iso caminho\da.iso] [-MemoriaMB 2048]
# Se o PowerShell bloquear scripts: powershell -ExecutionPolicy Bypass -File .\scripts\criar-vm.ps1
# Detalhes de cada comando: docs/01-configuracao-ambiente.md, seção 1.3.

param(
    [string]$Vm        = "incus-host",
    [string]$Iso       = "$env:USERPROFILE\Downloads\alpine-virt-3.24.4-x86_64.iso",
    [string]$Base      = "$env:USERPROFILE\VirtualBox VMs",
    [int]   $MemoriaMB = 2048,
    [int]   $Cpus      = 2,
    [int]   $DiscoMB   = 16384,
    [string]$Vbm       = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
)

$ErrorActionPreference = "Stop"

function V { & $Vbm @args; if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args -join ' ') falhou" } }

if (-not (Test-Path $Vbm)) { throw "VBoxManage não encontrado em $Vbm (ajuste -Vbm)" }
if (-not (Test-Path $Iso)) { throw "ISO não encontrada: $Iso (seção 1.2 do guia)" }

$esperado = "157D353F8E54252CAD2D9812A0D56BB7FA2231FC154A110E1D180D7480EF8B4F"
if ((Split-Path $Iso -Leaf) -eq "alpine-virt-3.24.4-x86_64.iso") {
    $hash = (Get-FileHash $Iso -Algorithm SHA256).Hash
    if ($hash -ne $esperado) { throw "SHA-256 da ISO não confere ($hash). Baixe de novo." }
    Write-Host "ISO conferida (SHA-256 ok)."
}

if ((& $Vbm list vms) -match "`"$Vm`"") { throw "A VM '$Vm' já existe. Para recriar: & '$Vbm' unregistervm $Vm --delete" }

Write-Host "VirtualBox $(& $Vbm --version)"

V createvm --name $Vm --ostype Linux_64 --basefolder "$Base" --register
V modifyvm $Vm --memory $MemoriaMB --cpus $Cpus --ioapic on `
    --graphicscontroller vmsvga --vram 16 --audio-enabled off `
    --boot1 dvd --boot2 disk --boot3 none --boot4 none
V modifyvm $Vm --nic1 nat

$disco = Join-Path $Base "$Vm\$Vm.vdi"
V storagectl $Vm --name SATA --add sata --controller IntelAhci --portcount 2
V createmedium disk --filename "$disco" --size $DiscoMB --format VDI
V storageattach $Vm --storagectl SATA --port 0 --device 0 --type hdd --medium "$disco"
V storageattach $Vm --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$Iso"

# Encaminhamento de portas: só 127.0.0.1 (não aciona o Firewall do Windows)
$regras = @(
    "ssh,tcp,127.0.0.1,2222,,22",
    "cenario,tcp,127.0.0.1,8080,,8080",
    "stats,tcp,127.0.0.1,8404,,8404",
    "painel,tcp,127.0.0.1,9000,,9000",
    "terminal,tcp,127.0.0.1,7681,,7681"
)
foreach ($r in $regras) { V modifyvm $Vm --nat-pf1 $r }

& $Vbm showvminfo $Vm --machinereadable | Select-String "^(memory|cpus|nic1|Forwarding)"

Write-Host ""
Write-Host "VM criada. Próximo passo: & '$Vbm' startvm $Vm --type gui  e rode 'setup-alpine' (seção 1.4)."
