module nt.sliceanddice;

import nt.books;
import nt.util;
import jsonizer;
import std.file;
import std.path;
import std.string;

void slice(string[] args)
{
    string input, output;
    import std.getopt : config;
    argparse(args, "Split a Bible into canonical categories",
            config.required,
            "i|input", "input bible", &input,
            config.required,
            "o|output", "output directory", &output);
    auto bible = readJSON!Bible(input);
    mkdirRecurse(output);
    foreach (cat, names; categories)
    {
        auto b = new Bible;
        b.name = bible.name ~ " -- " ~ cat;
        foreach (book; bible.books)
        {
            foreach (name; names)
            {
                if (book.name.toLower.indexOf(name) >= 0)
                {
                    b.books ~= book;
                }
            }
            writeJSON(buildPath(output, cat ~ ".json"), b);
        }
    }
}

void concat(string[] args)
{
    import std.getopt : config;
    string output;
    string name;
    argparse(args, "Combine several bibles into one",
            config.required,
            "o|output", "output bible", &output,
            "n|name", "name of combined bible", &name);
    auto bible = new Bible;
    foreach (input; args)
    {
        auto b = readJSON!Bible(input);
        bible.books ~= b.books;
        foreach (k, v; b.nameHistogram)
        {
            if (auto p = k in bible.nameHistogram)
            {
                (*p) += v;
            }
            else
            {
                bible.nameHistogram[k] = v;
            }
        }
    }
    writeJSON(output, bible);
}

enum categories = [
    "pentateuch": ["genesis", "exodus", "leviticus", "numbers", "deuteronomy"],
    "ot-narrative": [
        "joshua", "judges", "ruth", "samuel", "kings", "chronicles", "ezra",
        "nehemiah", "esther", "tobit", "judith", "esdras"],
    "wisdom": [
        "job", "psalms", "proverbs", "ecclesiastes", "solomon", "canticles", "wisdom",
        "sirach",],
    "prophecy": [
        "isaiah", "jeremiah", "lamentations", "ezekiel", "daniel", "hosea", "joel",
        "amos", "obadiah", "jonah", "micah", "nahum", "habakkuk", "zephaniah",
        "haggai", "zechariah", "malachi", "revelation"
    ],
    "nt-narrative": ["matthew", "mark", "luke", "john", "acts", "maccabee", "baruch",],
    "epistle": [
		"romans", "corinthians", "corinthians", "galatians", "ephesians",
		"philippians", "colossians", "thessalonians", "timothy", "titus", "philemon",
		"hebrews", "james", "peter", "jude",
		// John is a case of name collision, so we call that out separately
        "1 john", "2 john", "3 john", "1st john", "2nd john", "3rd john", "of john",
    ]
];
