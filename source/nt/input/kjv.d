/** Input processor for KJV, Project Gutenberg edition */
module nt.input.kjv;

import nt.books;
import nt.names;
import nt.nlp;
import nt.util;

import std.conv;
import std.json;
import std.stdio;
import std.string;
import std.algorithm;
import std.file;
import std.regex;
import sai = std.algorithm.iteration;
import std.typecons;

Bible importKJV(string path)
{
    return toKJVBible(path.readText);
}

Bible toKJVBible(string text)
{
    auto cvr = regex("([0-9]+):([0-9]+)");

    auto bible = new Bible("King James Bible");
    Book book;
    foreach (part; sai.splitter(text, "\n\n\n"))
    {
        auto p = part.strip;
        auto m = matchFirst(p, cvr);
        if (m.empty)
        {
            if (book) bible.books ~= book;
            book = new Book;
            book.name = p.strip;
            continue;
        }
        auto splat = std.regex.splitter!(Yes.keepSeparators)(p, cvr);
        while (!splat.empty)
        {
            m = matchFirst(splat.front, cvr);
            if (m.empty)
            {
                splat.popFront;
                m = matchFirst(splat.front, cvr);
            }
            auto ch = m[1].to!uint;
            auto v = m[2].to!uint;
            foreach (i; book.chapters.length .. ch)
            {
                book.chapters ~= new Chapter(cast(uint)i + 1);
            }

            splat.popFront;
            auto cleaned = splat.front
                // Paragraph separator isn't whitespace and won't get stripped
                .replace("\n\n", newParagraphMark)
                .strip
                .replace("\n", " ");
            auto verse = new Verse(v, cleaned);
            book.chapters[ch - 1].verses ~= verse;
            splat.popFront;
        }
    }
    bible.books ~= book;
    return bible;
}

