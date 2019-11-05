import std.stdio;

import nt.books;
import nt.markovgen;
import nt.publish;
import nt.wiktionary;
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
            import nt.input.kjv;
            writeJSON("kjv.json", importKJV(args[2]));
            return;
        case "bom":
            import nt.input.bom;
            writeJSON("bom.json", importBoM(args[2]));
            return;
        case "web":
            import nt.input.web;
            writeJSON("web.json", importWEB(args[2]));
            return;
        case "nlp":
            import nt.nlp;
            nlpMain(args[1..$]);
            return;
        case "find-names":
            import nt.names;
            findNamesMain(args[1..$]);
            return;
        case "find-themes":
            import nt.themes;
            findThemesMain(args[1..$]);
            return;
        case "build-chains":
            bakeBiblesMain(args[1..$]);
            return;
        case "generate-bible":
            generateBibleMain(args[1..$]);
            return;
        case "build-epub":
            auto bible = readJSON!Bible(args[2]);
            writeEpub(bible, bible.name ~ ".epub");
            return;
        case "merge-bibles":
            import std.getopt;
            auto a = args[1..$];
            string[] inputs;
            string output;
            auto opts = getopt(args,
                    config.required,
                    "i|inputs", "input bibles to merge", &inputs,
                    config.required,
                    "o|output", "output bible", &output);
            auto bibles = inputs.map!(x => readJSON!Bible(x));
            foreach (bible; bibles[1..$])
            {
                //bibles[0].append(bible);
            }
            writeJSON(output, bibles[0]);
            return;
        case "build-dict":
            importMain(args[1..$]);
            return;
        default:
            writefln("unrecognized option %s", args[1]);
            return;
    }
}

