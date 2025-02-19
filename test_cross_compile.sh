#/bin/sh

if [ $# != 1 -o "$1" == --help -o "$1" = -h ]; then
    echo "Usage: test_cross_comile.sh ROOT_SOURCE_DIRECTORY"
    exit 1
fi

rootsrc="$1"
[ -d "$rootsrc" ] || { echo "Directory '$1' not found." 1>&2; exit 1; }

[ -d julia-1.7.3 ] || curl -L https://julialang-s3.julialang.org/bin/linux/x86/1.7/julia-1.7.3-linux-i686.tar.gz | tar xzf -
cat <<EOF > build_root_tarball.jl
using Pkg

Pkg.activate(@__DIR__)
Pkg.add("BinaryBuilder")
Pkg.instantiate()

using BinaryBuilder

name = "ROOT"
version = v"0.0.0"

# Collection of sources required to complete build
sources = [
    DirectorySource("$rootsrc", target="root")
]

# Bash recipe for building across all platforms
script = raw"""

# In the sandbox set by BinarBuilder, g++ is a link to the cross-compiler
CROSS_COMPILER=g++

#Retrieves the system include path list for cross compilation. Note: 
export SYSTEM_INCLUDE_PATH="\`\$CROSS_COMPILER -E -x c++ -v /dev/null  2>&1  | awk '{gsub(\"^ \", \"\")} /End of search list/{a=0} {if(a==1){s=s d \$0;d=":"}} /#include <...> search starts here/{a=1} END{print s}'\`"

# build-in compilation of the libAfterImage library needs this directory
mkdir -p /tmp/user/0

cd "\$WORKSPACE"

# For the rootcling execution performed during the build:
echo "include_directories(SYSTEM /opt/\$target/\$target/sys-root/usr/include)" >> \${CMAKE_TARGET_TOOLCHAIN}

# Compile for the host binary used in the build process
# Davix is switched off, as otherwise build fails in buildkite CI. It should not be
# needed for the NATIVE tools. 
mkdir NATIVE
cmake -GNinja \\
     -DCXX_STANDARD=c++17 \\
     -DCLANG_DEFAULT_STD_CXX=cxx17 \\
     -DCMAKE_TOOLCHAIN_FILE=\${CMAKE_HOST_TOOLCHAIN} \\
     -DLLVM_HOST_TRIPLE=\$MACHTYPE \\
     -DCLING_CXX_PATH=g++ \\
     -DCLING_TARGET_GLIBC=1 \\
     -DCLING_TARGET_GLIBCXX=1 \\
     -DCLING_SYSTEM_INCLUDE_PATH="\$SYSTEM_INCLUDE_PATH" \\
     -Ddavix=OFF \\
     -Druntime_cxxmodules=OFF \\
     -B NATIVE -S srcdir/root

cmake --build NATIVE -- -j\$nproc rootcling_stage1 rootcling llvm-tblgen clang-tblgen llvm-config llvm-symbolizer


# CPLUS_INCLUDE_PATH used to set system include path for rootcling in absence
# of a -sysroot option. It should be transparent gcc and target build as it set the path 
# to the value obtained from gcc itself before setting CPLUS_INCLUDE_PATH and using
# the same sysroot option as for compilation.
export CPLUS_INCLUDE_PATH="\$SYSTEM_INCLUDE_PATH"
mkdir build
cmake -GNinja \\
      -DCXX_STANDARD=c++17 \\
      -DCLANG_DEFAULT_STD_CXX=cxx17 \\
      -DCMAKE_TOOLCHAIN_FILE=\${CMAKE_TARGET_TOOLCHAIN} \\
      -DCMAKE_INSTALL_PREFIX=\$prefix \\
      -DLLVM_HOST_TRIPLE=\$LLVM_TARGET \\
      -DLLVM_PARALLEL_LINK_JOBS=\$LLVM_PARALLEL_LINK_JOBS \\
      -DNATIVE_BINARY_DIR=\$PWD/NATIVE \\
      -DLLVM_TABLEGEN=\$PWD/NATIVE/interpreter/llvm-project/llvm/bin/llvm-tblgen \\
      -DCLANG_TABLEGEN=\$PWD/NATIVE/interpreter/llvm-project/llvm/bin/clang-tblgen \\
      -DLLVM_CONFIG_PATH=\$PWD/NATIVE/interpreter/llvm-project/llvm/bin/llvm-config \\
      -DCLING_SYSTEM_INCLUDE_PATH=\$SYSTEM_INCLUDE_PATH"
      -DCMAKE_BUILD_TYPE=\$BUILD_TYPE -DLLVM_BUILD_TYPE=\$BUILD_TYPE \\
      -DCLING_CXX_PATH=g++ \\
      -Druntime_cxxmodules=OFF \\
      -Dfound_urandom_EXITCODE=0 \\
      -Dfound_urandom_EXITCODE__TRYRUN_OUTPUT="" \\
      -B build -S srcdir/root


# Build the code
cmake --build build -j\$nproc

# Install the binaries
cmake --install build --prefix \$prefix
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Platform("x86_64", "linux"; libc = "glibc"),
]


# The products that we will ensure are always built
products = Product[
    ExecutableProduct("root", :root)
    ExecutableProduct("rootcling", :rootcling)
    ExecutableProduct("rootcling_stage1", :rootcling_stage1)
]

# Dependencies that must be installed before this package can be built
dependencies = [
    #Mandatory dependencies
    BuildDependency(PackageSpec(name="Xorg_xorgproto_jll", uuid="c4d99508-4286-5418-9131-c86396af500b"))
    Dependency(PackageSpec(name="Xorg_libX11_jll", uuid="4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"))
    Dependency(PackageSpec(name="Xorg_libXpm_jll", uuid="1a3ddb2d-74e3-57f3-a27b-e9b16291b4f2"))
    Dependency(PackageSpec(name="Xorg_libXft_jll", uuid="2c808117-e144-5220-80d1-69d4eaa9352c"))

    #Optionnal dependencies (if absent, either a feature will be disabled or a built-in version will be compiled)
    Dependency(PackageSpec(name="VDT_jll", uuid="474730fa-5ea9-5b8c-8629-63de62f23418"))
    Dependency(PackageSpec(name="XRootD_jll", uuid="b6113df7-b24e-50c0-846f-35a2e36cb9d5"))
    Dependency(PackageSpec(name="Lz4_jll", uuid="5ced341a-0733-55b8-9ab6-a4889d929147"))
    Dependency(PackageSpec(name="FFTW_jll", uuid="f5851436-0d7a-5f13-b9de-f02708fd171a"))
    Dependency(PackageSpec(name="Giflib_jll", uuid="59f7168a-df46-5410-90c8-f2779963d0ec"))
    Dependency(PackageSpec(name="Zstd_jll", uuid="3161d3a3-bdf6-5164-811a-617609db77b4"))
    Dependency(PackageSpec(name="PCRE2_jll", uuid="efcefdf7-47ab-520b-bdef-62a2eaa19f15"))
    Dependency(PackageSpec(name="Graphviz_jll", uuid="3c863552-8265-54e4-a6dc-903eb78fde85"))
    Dependency(PackageSpec(name="xxHash_jll", uuid="5fdcd639-92d1-5a06-bf6b-28f2061df1a9"))
    Dependency(PackageSpec(name="XZ_jll", uuid="ffd25f8a-64ca-5728-b0f7-c24cf3aae800"))
    Dependency(PackageSpec(name="Librsvg_jll", uuid="925c91fb-5dd6-59dd-8e8c-345e74382d89"))
    Dependency(PackageSpec(name="FreeType2_jll", uuid="d7e528f0-a631-5988-bf34-fe36492bcfd7"))
    Dependency(PackageSpec(name="Xorg_libICE_jll", uuid="f67eecfb-183a-506d-b269-f58e52b52d7c"))
    Dependency(PackageSpec(name="Xorg_libSM_jll", uuid="c834827a-8449-5923-a945-d239c165b7dd"))
    Dependency(PackageSpec(name="Xorg_libXfixes_jll", uuid="d091e8ba-531a-589c-9de9-94069b037ed8"))
    Dependency(PackageSpec(name="Xorg_libXi_jll", uuid="a51aa0fd-4e3c-5386-b890-e753decda492"))
    Dependency(PackageSpec(name="Xorg_libXinerama_jll", uuid="d1454406-59df-5ea1-beac-c340f2130bc3"))
    Dependency(PackageSpec(name="Xorg_libXmu_jll", uuid="6bc1fdef-f8f4-516b-84c1-6f5f86a35b20"))
    Dependency(PackageSpec(name="Xorg_libXt_jll", uuid="28c4a263-0105-5ca0-9a8c-f4f6b89a1dd4"))
    Dependency(PackageSpec(name="Xorg_libXtst_jll", uuid="b6f176f1-7aea-5357-ad67-1d3e565ea1c6"))
    Dependency(PackageSpec(name="Xorg_xcb_util_jll", uuid="2def613f-5ad1-5310-b15b-b15d46f528f5"))
    Dependency(PackageSpec(name="Xorg_libxkbfile_jll", uuid="cc61e674-0454-545c-8b26-ed2c68acab7a"))
    Dependency(PackageSpec(name="Libglvnd_jll", uuid="7e76a0d4-f3c7-5321-8279-8d96eeed0f29"))
    Dependency(PackageSpec(name="GLU_jll", uuid="bd17208b-e95e-5925-bf81-e2f59b3e5c61"))
    Dependency(PackageSpec(name="GLEW_jll", uuid="bde7f898-03f7-559e-8810-194d950ce600"))
    Dependency(PackageSpec(name="CFITSIO_jll", uuid="b3e40c51-02ae-5482-8a39-3ace5868dcf4"))
    Dependency(PackageSpec(name="oneTBB_jll", uuid="1317d2d5-d96f-522e-a858-c73665f53c3e"), compat="2021.9.0")
    Dependency(PackageSpec(name="OpenBLAS32_jll", uuid="51095b67-9e93-468d-a683-508b52f74e81"))
]

# Build the tarballs, and possibly a \`build.jl\` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies; julia_compat="1.6", preferred_gcc_version=v"12", verbose=true, debug=true)

println("Tarball saved in the products directory.")
EOF

[ $? = 0 ] && julia-1.7.3/bin/julia build_root_tarball.jl
