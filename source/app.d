import std.stdio;

import nt.books;
import nt.markovgen;
import nt.publish;
import nt.themes;
import nt.util;
import nt.wiktionary;

import arsd.dom;
import jsonizer;

import etc.linux.memoryerror;
import std.algorithm;
import std.array;
import std.experimental.logger;
import std.getopt;
import std.path;
import std.file;
import std.string;

void main(string[] args)
{
    registerMemoryErrorHandler();
    globalLogLevel = LogLevel.trace;
    if (args.length == 1) return;
    auto rest = args[1 .. $];
    doMain(args[0], rest);
}

void doMain(string exeName, string[] rest)
{
    switch (rest[0])
    {
        case "prepare-input":
            string type, input, outdir;
            argparse(rest, "Fully prepare input from base sources.\n"
                    ~ "This does everything to the input that can be done without "
                    ~ "tuning parameters.",
                    config.required,
                    "t|type", "the type of bible that the input is", &type,
                    config.required,
                    "i|input", "the input bible file", &input,
                    config.required,
                    "o|outdir", "the output directory", &outdir);
            mkdirRecurse(outdir);
            auto rawBible = buildPath(outdir, "bible.json");
            auto nlpBible = buildPath(outdir, "bible-nlp.json");
            auto nameBible = buildPath(outdir, "bible-name.json");
            doMain(exeName, ["import", "-t", type, "-i", input, "-o", rawBible]);
            doMain(exeName, ["nlp", "-i", rawBible, "-o", nlpBible]);
            doMain(exeName, ["find-names", "-i", nlpBible, "-o", nameBible]);

            writefln("Done! To build the model:");
            writefln("  %s prepare-model -i %s -o mymodel [args]", exeName, nameBible);
            writefln("For more info on the possible arguments:");
            writefln("  %s prepare-model --help");
            return;

        case "prepare-model":
            string input, outdir, nameContext = "1-3", themeContext = "2-3", themeFreq = "20-1000";
            argparse(rest, "Prepare the model from a prepared input",
                    config.required,
                    "i|input", "input bible", &input,
                    config.required,
                    "o|outdir", "directory to store the output", &outdir,
                    "n|name-context", "range of characters for name context", &nameContext,
                    "t|theme-context", "range of verses for theme context", &themeContext,
                    "f|theme-frequency",
                        "how frequent a word can be to be considered as a theme candidate",
                        &themeContext,
                    );
            auto bible = readJSON!Bible(input);

            // Themes!
            ThemeModel themes;
            auto tf = Interval(themeFreq);
            themes.minOccurrences = tf.min;
            themes.maxOccurrences = tf.max;
            themes.build(bible);
            writeJSON(buildPath(outdir, "themes.json"), themes);
            writeJSON(buildPath(outdir, "bible-themes.json"), bible);

            // Chains!
            buildThemeChain(bible, buildPath(outdir, "themes.chain"), Interval(themeContext));
            buildNameChain(bible, buildPath(outdir, "names.chain"), Interval(nameContext));
            writefln("Done! To build the ebook:");
            writefln("  %s create-bible -m %s [args]", exeName, outdir);
            writefln("For more info on the possible arguments:");
            writefln("  %s create-bible --help");
            return;

        case "import":
            import nt.input.kjv;
            import nt.input.bom;
            import nt.input.web;
            string input, output, type;
            argparse(rest, "Import a bible from original sources",
                    config.required,
                    "t|type", &type,
                    config.required,
                    "i|input", &input,
                    config.required,
                    "o|output", &output);
            Bible bible;
            type = type.toLower;
            if (type == "kjv")
                bible = importKJV(input);
            else if (type == "bom")
                bible = importBoM(input);
            else if (type == "web")
                bible = importWEB(input);
            else
            {
                stderr.writefln("unrecognized bible type '%s'", type);
                import core.stdc.stdlib : exit;
                exit(1);
            }
            writeJSON(output, bible);
            return;
        case "jsonimport":
            import nt.dictionary;
            break;
        case "nlp":
            import nt.nlp;
            nlpMain(rest);
            return;
        case "nlp-render":
            import nt.nlp;
            nlpRenderMain(rest);
            return;
        case "find-names":
            import nt.names;
            findNamesMain(rest);
            return;
        case "find-themes":
            import nt.themes;
            findThemesMain(rest);
            return;
        case "build-chains":
            bakeBiblesMain(rest);
            return;
        case "generate-bible":
            generateBibleMain(rest);
            return;
        case "swap-names":
            import nt.names;
            import std.random;
            import markov;
            import std.range;
            import std.algorithm;
            import std.string;
            string input, output, chainFile;
            uint seed = unpredictableSeed;
            argparse(rest, "Swap names in NLP bible",
                    config.required,
                    "i|input", "input bible", &input,
                    config.required,
                    "o|output", "output bible", &output,
                    config.required,
                    "c|chain", "name markov chain", &chainFile,
                    "s|seed", "random number seed", &seed);
            rndGen.seed(seed);
            auto chain = decodeBinary!string(File(chainFile, "r"));
            auto bible = readJSON!Bible(input);
            auto names = iota(500)
                .map!(x => chain.generate(uniform(4, 10)).join(""))
                .array
                .sort
                .uniq
                .array;
            tracef("got %s names from chain", names.length);
            swapNames(bible, names, 3, 4);
            writeJSON(output, bible);
            return;
        case "build-epub":
            auto bible = readJSON!Bible(rest[1]);
            writeEpub(bible, bible.name ~ ".epub");
            return;
        case "split-canonical":
            import nt.sliceanddice;
            slice(rest);
            return;
        case "merge-bibles":
            import nt.sliceanddice;
            concat(rest);
            return;
        case "build-dict":
            importMain(rest);
            return;
        default:
            writefln("unrecognized option %s", rest[0]);
            return;
    }
}

