#!/bin/sh

export CERB_PATH=/local/jenkins/home/workspace/rems/cerberus
export DEPPATH=$CERB_PATH/dependencies
export OPAMROOT=$DEPPATH/.opam
export BINPATH=$DEPPATH/bin
export PATH=$BINPATH:$PATH

if ! hash opam 2> /dev/null; then
  echo "Installing OPAM!"
  mkdir -p $BINPATH
  wget https://raw.github.com/ocaml/opam/master/shell/opam_installer.sh -O - | sh -s $BINPATH 4.06.0
  opam init
  opam install ocamlfind cmdliner menhir pprint zarith yojson z3
fi

if ! hash lem 2> /dev/null then
  echo "Install LEM"
  cd $DEPPATH
  git clone https://github.com/rems-project/lem
  cd lem
  make
  cd ocaml-lib
  make install
  cd $CERB_PATH
fi


