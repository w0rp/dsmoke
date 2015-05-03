# w0rp's Visual Studio smokeqt build guide

*Special thanks goes to burel on the kde-bindings IRC channel.*

Install the latest Qt 4.8 (or whatever you want) for Windows (VS 2010).
You can find the downloads here: https://qt-project.org/downloads

Put the Qt bin directory in your PATH.

Install msbuild.exe, or Visual Studio, 2010 or above.

Install CMake.

Clone the smoke repositories.

```batch
git clone git://anongit.kde.org/smokegen
git clone git://anongit.kde.org/smokeqt
```

Use CMake to set up smokegen.

```batch
cd smokegen
cmake .
```

Build the project for Release with msbuild. (or use Visual Studio)

```batch
msbuild smokegenerator.sln /p:Configuration=Release
```

Now install everything that was built. (Run as admin)

```batch
cmake -P cmake_install.cmake
```

Run cmake again in the smokeqt directory, pointing at smokegen's files.
You will have to give CMake for smokeqt the **absolute** path to your smokegen
directory.

```
cd ..\smokeqt
cmake -DSmoke_DIR=<put your absolute path here>\smokegen\cmake .
```

Build the project for Release with msbuild. (or use Visual Studio)

```batch
msbuild SMOKEQT4.sln /p:Configuration=Release
```

Now install the smokeqt stuff.

```batch
cmake -P cmake_install.cmake
```

The above install command will dump it to the root directory of the drive
you are on, but you can go ahead and move that into the same place
smokegen installed to in Program Files.

