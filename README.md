<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/icon-dark.png">
  <img src="docs/icon.png" width="140" alt="Ícone do DeviceBar">
</picture>

# DeviceBar

**Emuladores Android e simuladores iOS a um clique, direto da barra de menus do Mac.**

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-1DB97A)

<img src="docs/menu.png" width="360" alt="Menu do DeviceBar">

</div>

Ligar um emulador não deveria exigir abrir o Android Studio ou o Xcode inteiros. O DeviceBar mostra todos os seus aparelhos virtuais num só menu: um clique liga, outro desliga.

- **Android**: liga suas AVDs. Segure **⌥** para fazer *cold boot*.
- **iOS**: simuladores de iPhone e iPad, agrupados por versão do iOS.
- **✓ no que está rodando**, com opções para mostrar ou parar.
- **Leve**: um único arquivo Swift, sem dependências e com 0% de CPU enquanto o menu está fechado.

## Instalação

Requer macOS 13+ em Apple Silicon e Xcode 26+. Para os emuladores Android, também é preciso o Android SDK.

```sh
git clone https://github.com/andersonmendess/DeviceBar.git
cd DeviceBar
./build.sh install
open ~/Applications/DeviceBar.app
```

Se o SDK não estiver em `~/Library/Android/sdk`, defina `ANDROID_HOME`.

## Licença

[MIT](LICENSE)
