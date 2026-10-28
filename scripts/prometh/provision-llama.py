#!/usr/bin/env python3
"""Build the pinned, relocatable API-only llama server used by Prometh.

Prometh owns file/shell/MCP tools and their approvals. The engine therefore
ships no second built-in filesystem/shell tool implementation or embedded UI.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
REF='620d2225cc436ab0b001e3200e590e3b286ef9ab'  # b11669


def run(command):
    print('+',' '.join(command),flush=True)
    subprocess.run(command,check=True)


def main():
    with tempfile.TemporaryDirectory(prefix='prometh-llama-') as temporary:
        source=Path(temporary)/'source'
        build=Path(temporary)/'build'
        run(['git','init','-q',str(source)])
        run(['git','-C',str(source),'fetch','-q','--depth','1','https://github.com/ggml-org/llama.cpp',REF])
        run(['git','-C',str(source),'checkout','-q','FETCH_HEAD'])
        tools=source/'tools/server/server-tools.cpp'
        text=tools.read_text()
        start=text.index('static std::vector<std::unique_ptr<server_tool>> build_tools() {')
        end=text.index('\n}\n',start)+3
        text=text[:start]+'''static std::vector<std::unique_ptr<server_tool>> build_tools() {
    // Prometh owns tool execution and approvals; this engine is inference-only.
    return {};
}
'''+text[end:]
        original='        runtime = make_tools_runtime(tools_runtime);'
        assert text.count(original)==1
        text=text.replace(original,'        throw std::runtime_error("Prometh manages tool execution in the app.");')
        tools.write_text(text)
        flags=f'-ffile-prefix-map={source}=/src/llama -fdebug-prefix-map={source}=/src/llama'
        run(['cmake','-S',str(source),'-B',str(build),'-DCMAKE_BUILD_TYPE=Release',
             '-DCMAKE_OSX_ARCHITECTURES=arm64','-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0',
             '-DBUILD_SHARED_LIBS=ON','-DGGML_NATIVE=OFF','-DGGML_METAL_EMBED_LIBRARY=ON',
             '-DLLAMA_BUILD_TESTS=OFF','-DLLAMA_BUILD_EXAMPLES=OFF','-DLLAMA_BUILD_APP=OFF',
             '-DLLAMA_BUILD_SERVER=ON','-DLLAMA_BUILD_UI=OFF','-DLLAMA_USE_PREBUILT_UI=OFF',
             '-DLLAMA_OPENSSL=OFF',f'-DCMAKE_C_FLAGS={flags}',f'-DCMAKE_CXX_FLAGS={flags}',
             '-DCMAKE_BUILD_RPATH=@loader_path'])
        run(['cmake','--build',str(build),'--target','llama-server','--parallel',str(min(os.cpu_count() or 4,12))])
        output=ROOT/'PromethRuntime/llama/bin'
        output.mkdir(parents=True,exist_ok=True)
        files=[p for p in (build/'bin').iterdir() if p.name=='llama-server' or '.dylib' in p.name]
        assert any(p.name=='llama-server' for p in files)
        # Validate before updating the gitignored target; no model/data files.
        for p in files:
            if not p.is_symlink():
                assert b'.venv' not in p.read_bytes(),f'unused tool code retained in {p.name}'
        for p in output.iterdir():
            if p.is_file() or p.is_symlink():p.unlink()
        for p in files:
            if p.is_symlink(): (output/p.name).symlink_to(os.readlink(p))
            else: shutil.copy2(p,output/p.name)
        shutil.copy2(source/'LICENSE',output/'LICENSE')
        run([str(output/'llama-server'),'--version'])


if __name__=='__main__':main()
