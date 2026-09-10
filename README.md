Este proyecto es un intento de hacer un juegos en tercera persona de plataformas con Lovr, un motor 3d/vr super simple que da resultados al toque.

### Como levantar el proyecto

> Primero debemos descargar Lovr para tu SO si es linux el AppImage si es windows el .exe en https://lovr.org/downloads
> Tambien descargar el `lovr-mouse.lua` de https://github.com/bjornbytes/lovr-mouse

Crea una carpeta donde te canten los huevinis que tenga dentro en plan:

```
./lovr/lovr-mouse.lua
./lovr/lovr-x86_64.AppImage (en linux)
./lovr/lovr-xxx.exe (en windows)
```

Con eso listo todo lo que tienes que hacer es ejecutar el comando en powershell, cmd, terminal o lo que tengas:

`./lovr/lovr-x86_64.AppImage main.lua`

> lo mismo con windows pero en lugar del AppImage seria el .exe

Si estas en Windows puedes arrastrar el main.lua al .exe de lovr y se va a ejecutar.

Gracias hasta luego.