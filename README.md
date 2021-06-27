[![Build](https://github.com/typedb-osi/typedb-client-haskell/actions/workflows/main.yml/badge.svg?branch=master)](https://github.com/typedb-osi/typedb-client-haskell/actions/workflows/main.yml)

# TypeDB Client for Haskell (INCUBATING)

This is a TypeDB client implementation for Haskell.
It uses AwakeSecurity's gRPC library to implement the TypeDB Protocol.
There are three versions planned (all within this package):

- Type-Safe-Client: Haskell code compiled along with a TypeDB schema 
  to support strongly typed queries and other operations for a specific Schema
- High-Level-Client: A nice API for the TypeDB Protocol and most needs.
- Low-Level-Client: a usable wrapper around the generated gRPC Code.
  
## Building
This project uses Nix.
To get a development environment use 
```sh
> nix-shell
```

Building from within the dev env:
```sh
> cabal build
```

to build the project in one command:
```sh 
> nix-shell --command "cabal update && cabal build"
```

 ## Status

the haskell client successfully performed its' first action:
- querying the available DBs,
- creating a new one
- initializing it with a schema 
- committing the whole thing
- closing the connection

query DSL compiles to proper query strings

still a long road to go; but nevertheless a small victory ^^

 *Beware:* Currently, the core code is messy, there is not much testing and there are
 still design choices planned that are subject to change if I see fit. 
 Enter at own risk ;)
 
 ## Contributing
 Right now this is a university project of mine. 
 A basic client should be the outcome of the project (for my university at least).
 
 If you want to contribute, please reach out via mail, discord or by issue
 or even a pull request if you are very eager.
 (But please don't be disapointed if I take some time to answer/merge pull requests
 because I have loads of different projects to handle right now.)
 
