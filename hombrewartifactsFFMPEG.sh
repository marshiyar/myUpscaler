for f in myUpscaler/lib/*.dylib; do
  echo "== $f =="
  otool -L "$f" | grep homebrew || true
done
