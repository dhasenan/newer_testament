/** Input processor for KJV, Project Gutenberg edition */
module nt.kjv;

import nt.books;

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
    auto cvr = regex("([0-9]+):([0-9]+)");
    auto text = path.readText;

    auto bible = Bible("King James Bible");
    Book book;
    foreach (part; sai.splitter(text, "\n\n\n"))
    {
        auto p = part.strip;
        auto m = matchFirst(p, cvr);
        if (m.empty)
        {
            if (book != Book.init) bible.books ~= book;
            book = Book.init;
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
                book.chapters ~= Chapter(cast(uint)i + 1);
            }

            splat.popFront;
            auto cleaned = splat.front
                // Paragraph separator isn't whitespace and won't get stripped
                .replace("\n\n", "\u2029")
                .strip
                .replace("\n", " ");
            auto verse = Verse(v, cleaned);
            book.chapters[ch - 1].verses ~= verse;
            splat.popFront;
        }
    }
    bible.books ~= book;
    return bible;
}
