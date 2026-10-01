#!/usr/bin/env python3
"""Verify released model bytes and the RGB tensor contract before packaging."""
import hashlib
import json
import pathlib
import sys


def verify(root):
    manifest = json.loads(pathlib.Path(__file__).with_name('coreml-models-manifest.json').read_text())
    for model in manifest['models']:
        folder = root / (model['name'] + '.mlmodelc')
        for relative, expected in model['sha256'].items():
            path = folder / relative
            # Check the model tree only: macOS /var and /tmp themselves are symlinks.
            parents = [folder / p for p in pathlib.Path(relative).parents]
            if any(p.is_symlink() for p in [folder, path, *parents]):
                raise ValueError(f'Symlink in model path: {path}')
            if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise ValueError(f'Model checksum mismatch: {path}')
        metadata = json.loads((folder / 'metadata.json').read_text())[0]
        for key, shape_key in [('inputSchema', 'inputShape'), ('outputSchema', 'outputShape')]:
            schema = metadata[key]
            if len(schema) != 1 or schema[0]['dataType'] != 'Float32':
                raise ValueError(f'Unsupported model schema: {folder}')
            if json.loads(schema[0]['shape']) != model[shape_key]:
                raise ValueError(f'Unexpected model shape: {folder}')
        source, output = model['inputShape'], model['outputShape']
        if (len(source) != 4 or len(output) != 4 or source[:2] != [1, 3]
                or output[:2] != [1, 3] or min(source[2:]) <= 16
                or output[2:] != [n * model['nativeScale'] for n in source[2:]]):
            raise ValueError(f'Model is incompatible with RGB tiling: {folder}')
    if (root / 'RealESRGAN_x2.mlmodelc').exists():
        raise ValueError('The released x2 model requires 12 channels and must not be bundled.')
    print('Verified bundled Real-ESRGAN x4 and x8 checksums and RGB tensor contracts.')


if __name__ == '__main__':
    try:
        verify(pathlib.Path(sys.argv[1]))
    except (OSError, ValueError, KeyError, IndexError) as error:
        sys.exit(f'CoreML assets: {error}')
