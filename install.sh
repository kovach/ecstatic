#!/bin/sh
# requires syb, happy, alex
# happy, alex on path
set -e
git clone https://github.com/kovach/mm.git simplifier
cd simplifier
git checkout 2025650691f1394b2e74b7665baff283757c041b
touch simplify/LICENSE
cd ..
cabal unpack language-c-0.4.7
cd language-c-0.4.7
patch -p1 < ../language-c-0.4.7.patch
cd ..
cabal sandbox init
cabal sandbox add-source language-c-0.4.7
cabal sandbox add-source simplifier/simplify
# needed for language-c:
# cabal install syb happy alex
# add happy/alex to the path
cabal install --dependencies-only
cabal build
