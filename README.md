# WinAutoTheme

Alterna o tema do Windows 11 automaticamente: **claro de dia**, **escuro à noite**.

O Windows 11 não tem essa opção nativa nas Configurações. Este script grava as chaves de personalização do usuário e avisa o Explorer para aplicar o modo na hora.

## Instalação

No **PowerShell do Windows** (não no WSL):

```powershell
cd caminho\para\winautotheme
Set-ExecutionPolicy -Scope Process Bypass
.\WinAutoTheme.ps1 -Install
```

Ou dê dois cliques em `install.bat`.

A instalação copia o script para `%LOCALAPPDATA%\WinAutoTheme` e cria a tarefa agendada `WinAutoTheme`. Ela roda **sem janela** no logon, ao desbloquear o PC e nos horários claro/escuro (não a cada poucos minutos).

Se a tarefa já estava instalada, rode `-Install` de novo para aplicar essa correção.

## Uso

| Comando | Efeito |
|---|---|
| `.\WinAutoTheme.ps1` | Aplica o tema do horário atual |
| `.\WinAutoTheme.ps1 -Light` | Força o tema claro |
| `.\WinAutoTheme.ps1 -Dark` | Força o tema escuro |
| `.\WinAutoTheme.ps1 -Status` | Mostra tema atual e horários |
| `.\WinAutoTheme.ps1 -Uninstall` | Remove tarefa e arquivos |

## Configuração

Edite `%LOCALAPPDATA%\WinAutoTheme\config.json`:

```json
{
  "mode": "fixed",
  "lightAt": "07:00",
  "darkAt": "19:00",
  "latitude": -23.5505,
  "longitude": -46.6333,
  "applyToApps": true,
  "applyToSystem": true,
  "wallpaperLight": "",
  "wallpaperDark": ""
}
```

- `mode`: `fixed` usa `lightAt` / `darkAt`. `sunrise` usa nascer e pôr do sol nas coordenadas.
- `latitude` / `longitude`: padrão em São Paulo. Troque pela sua cidade se usar `sunrise`.
- `wallpaperLight` / `wallpaperDark`: caminhos opcionais de imagem.

A tarefa usa `wscript.exe` + `WinAutoTheme.vbs` para não piscar o console do PowerShell.

## Desinstalação

```powershell
.\WinAutoTheme.ps1 -Uninstall
```

Ou `uninstall.bat`.
