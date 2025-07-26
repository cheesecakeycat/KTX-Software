This is a Zig package for [KTX-Software](https://github.com/KhronosGroup/KTX-Software/). All unnecessary files has been removed and build system was replaced with `build.zig`.

Designed to be used on Zig master (Nightly). Last tested on `0.15.0-dev.1222+5fb36d260`. (2025-07-26)

Feel free to create pull requests if the library does not compile for the latest Zig version.

# Usage
### Adding to your project

1. Add this repository as a dependency in your `build.zig.zon`. You can do it manually or by running the following command in your project's root directory:

```sh

zig fetch --save git+https://github.com/cheesecakeycat/KTX-Software.git

```
2. In your `build.zig`, add the dependency and link it to your artifact:

```zig
const target = ...;
const optimize = ...;
const mod = b.addModule(...);
const exe = b.addExecutable(...);

const ktx_dep = b.dependency("ktx_software", .{
    .target = target,
    .optimize = optimize,
    // you can override the options here. See [build.zig](https://github.com/cheesecakeycat/KTX-Software/blob/main/build.zig/#L8-L14) for more details.
    // .ktx2 = true,
});

mod.addImport("ktx", ktx_dep.module("libktx"));
mod.linkLibrary(ktx_dep.artifact("ktx"));
```
