import std.stdio;

import nt.books;
import nt.db;
import nt.markovgen;
import nt.names;
import nt.nlp;
import nt.publish;
import nt.sliceanddice;
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

string exeName;

void main(string[] args)
{
    registerMemoryErrorHandler();
    if (args.length == 1) return;
    foreach (arg; args)
    {
        if (arg == "-v" || arg == "--verbose")
        {

        }
    }
    globalLogLevel = LogLevel.trace;
    auto rest = args[1 .. $];
    exeName = args[0];
    doMain(rest);
}

void showHelp(string[] args)
{
    if (args.length == 2)
    {
        doMain([args[1], "--help"]);
        return;
    }
    string padding;
    ulong maxLength = 0;
    foreach (cmd; commands)
    {
        while (padding.length < cmd.name.length) padding ~= " ";
    }
    padding ~= "   ";
    writefln("%s COMMAND [OPTIONS]", exeName);
    writefln("Create a new bible");
    foreach (cmd; commands)
    {
        writefln("  %s%s%s", cmd.name, padding[cmd.name.length .. $], cmd.help);
    }
}

alias MainFn = void function(string[]);
struct Command
{
    string name;
    string help;
    MainFn fn;
}

Command[] commands = [
    Command("help", "Show this help message", &showHelp),
    Command("import", "Import a bible from source", &importBible),
    Command("nlp", "NLP-analyze a bible", &nlpMain),
    Command("nlp-render", "Turn an NLP-only bible back into text", &nlpRenderMain),
    Command("find-names", "Locate the names in a bible", &findNamesMain),
    Command("find-themes", "Create a theme model for a bible", &findThemesMain),
    Command("build-chains", "Build markov chains for a bible", &bakeBiblesMain),
    Command("generate-bible", "Generate a bible", &generateBibleMain),
    Command("swap-names", "Alter names to protect the guilty", &swapNamesMain),
    Command("build-epub", "Turn a bible into an epub document", &buildEpubMain),
    Command("split-canonical", "Split a bible by canonical categories", &slice),
    Command("merge-bibles", "Merge several bibles into one", &concat),
    Command("build-dict", "Import wiktionary / mythes dictionary data", &importMain),
    Command("list-bibles", "List available bibles", &listBiblesMain),
];

void importBible(string[] args)
{
    import nt.input.kjv;
    import nt.input.bom;
    import nt.input.web;
    string input, type;
    string database = ":memory:";
    argparse(args, "Import a bible from original sources",
            config.required,
            "t|type", "the kind of bible (kjv, bom, web)", &type,
            config.required,
            "i|input", "input file", &input,
            "d|database", "sqlite database to store bible in", &database);
    DB db = new DB(database);
    scope (exit) db.cleanup;

    db.beginTransaction;
    Bible bible;
    type = type.toLower;
    if (type == "kjv")
        bible = importKJV(input, db);
    else if (type == "bom")
        bible = importBoM(input, db);
    else if (type == "web")
        bible = importWEB(input, db);
    else
    {
        stderr.writefln("unrecognized bible type '%s'", type);
        import core.stdc.stdlib : exit;
        exit(1);
    }
    db.commit;
    writefln("imported bible %s", bible.id);
}

void swapNamesMain(string[] args)
{
    import nt.names;
    import std.random;
    import markov;
    import std.range;
    import std.algorithm;
    import std.string;
    string input, output, chainFile;
    uint seed = unpredictableSeed;
    argparse(args, "Swap names in NLP bible",
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
}

void buildEpubMain(string[] args)
{
    auto bible = readJSON!Bible(args[1]);
    writeEpub(bible, bible.name ~ ".epub");
}

void doMain(string[] rest...)
{
    foreach (cmd; commands)
    {
        if (cmd.name == rest[0])
        {
            cmd.fn(rest);
            return;
        }
    }
    showHelp(["help"]);
}

/+
void mainScript(string[] args)
{
    string database;
    argparse(args, "Generate default bible",
            config.required, "d|database", &db);

    import d2sqlite3;
    auto db = Database(database);

    doMain("import", "-t", "web", "-i", "input/eng-web_usfm.zip", "-d", database);
    auto bible = db.run("SELECT MAX(id) FROM bibles").oneResult!ulong;

    auto childBibles = slice(database, bible);
    ulong[string] modelByCategory;
    foreach (name, id; childBibles)
    {
        doMain("nlp", "-d", database, "-b", id.to!string);
        auto themeName = format("%s - %s standard", name, id);
        doMain("find-themes",
                "-d", database,
                "-n", themeName,
                "-l", "500",
                "-o", "10-1000");
        auto themeId = db.run("SELECT id FROM ThemeModels WHERE name = '" ~ themeName ~ "'")
            .oneValue!ulong
            .to!string;
        doMain("find-names", "-d", database, "-b", id.to!string, "-s", "name_stopwords.txt");
        doMain("build-chains", "-d", database, "-m", themeId, "-V", "2-5", "-n", "2-3");
        auto bibleName = "Poorman's " ~ name.titleCase;
        doMain("generate-bible",
                "-d", database,
                "-m", themeId,
                "-s", "1",
                "-n", bibleName,
                "-b", "5-10",
                "-e", "output/" ~ bibleName ~ ".epub");
    }
}
+/

void listBiblesMain(string[] args)
{
}
