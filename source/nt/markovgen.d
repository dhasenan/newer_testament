/** Generator for the markov model. */
module nt.markovgen;

import nt.books;
import markov;
import std.stdio;
import std.string;
import std.algorithm;
import std.json;
import std.algorithm;
import jsonizer;
import std.range;
import std.file;

void bakeBiblesIntoChain(string[] args)
{
    auto outfile = args[0];
    auto inputs = args[1..$];
    auto verses = MarkovChain!string(2, 3, 4);
    //auto books = MarkovChain!string(1, 2);

    foreach (input; inputs)
    {
        auto bible = readJSON!Bible(input);
        foreach (book; bible.books)
        {
            //books.train(book.name);
            foreach (chapter; book.chapters)
            {
                foreach (verse; chapter.verses)
                {
                    auto words = verse.text
                        /*
                        .toLower
                        .replace(";", "")
                        .replace(",", "")
                        .replace(":", "")
                        .replace("?", "")
                        .replace("!", "")
                        */
                        .split(" ");
                    verses.train(words);
                }
                //verses.train(chapter.verses.map!(x => x.text).array);
            }
        }
    }
    auto v = verses.encodeJSON.parseJSON;
    //auto b = books.encodeJSON.parseJSON;
    JSONValue val;
    val["verses"] = v;
    //val["books"] = b;
    auto f = File(outfile, "w");
    f.write(val.toPrettyString);
    f.close;
}

Bible generateBibleFromChain(string chainFile)
{
    JSONValue c = readText(chainFile).parseJSON;
    auto verses = c["verses"].toString.decodeJSON!string;
    //auto books = c["books"].toString.decodeJSON!char;

    import std.random;

    Bible bible;
    foreach (booknum; 1 .. uniform(5, 20))
    {
        Book book;
        import std.format : format;
        book.name = format("Book %s", booknum);
        //book.name = books.generate;
        foreach (chapternum; 1 .. uniform(1, 10))
        {
            verses.reset;
            Chapter chapter;
            chapter.chapter = chapternum;
            chapter.verses = iota(uniform(5, 10))
                .map!(x => verses.generate(uniform(10, 25)).join(" "))
                .enumerate
                .map!(t => Verse(cast(uint)t[0] + 1, t[1]))
                .array;
            book.chapters ~= chapter;
        }
        bible.books ~= book;
    }
    return bible;
}
