import std.stdio;

import nt.books;
import nt.markovgen;
import etc.linux.memoryerror;

import arsd.dom;
import jsonizer;
import std.algorithm;
import std.array;
import std.experimental.logger;

void main(string[] args)
{
    registerMemoryErrorHandler();
    globalLogLevel = LogLevel.trace;
    if (args.length == 1) return;
    switch (args[1])
    {
        case "kjv":
            import nt.kjv;
            writeJSON("kjv.json", importKJV(args[2]));
            return;
        case "bom":
            import nt.bom;
            writeJSON("bom.json", importBoM(args[2]));
            return;
        case "bake":
            bakeBiblesIntoChain(args[2 .. $]);
            return;
        case "gen":
            auto bible = generateBibleFromChain(args[2]);
            writeJSON(args[3], bible);
            return;
        case "format":
            auto bible = readJSON!Bible(args[2]);
            return;
        default:
            writefln("unrecognized option %s", args[1]);
            return;
    }
}

