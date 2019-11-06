module nt.publish;

import nt.books;
import nt.util;

import ep = epub;
import std.process;
import std.algorithm;
import std.array;
import std.conv;
import std.format;

enum style = `
div.scripture {
    text-indent: 1em;
    margin-bottom: 1em;
}
span.verseid {
    font-size: 60%;
    font-weight: bold;
    vertical-align: text-top;
}
h2 {
    font-size: 120%;
}
`;

void writeEpub(Bible bible, string file)
{
    auto b = new ep.Book;
    b.title = bible.name;
    b.author = environment["USER"];
    b.chapters = bible.books
        .map!toEpubChapter
        .array;
    b.attachments ~= ep.Attachment("stylecss", "style.css", "text/css", cast(const(ubyte)[])style);
    ep.toEpub(b, file);
}

ep.Chapter toEpubChapter(Book book)
{
    Appender!string a;
    a ~= `<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
  <head>
    <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
    <title>`;
    a ~= book.name;
    a ~= `</title>
    <link rel="stylesheet" type="text/css" href="style.css"/>
  </head>
  <body>
    <h1>`;
    a ~= book.name;
    a ~= `</h1>`;
    foreach (i, c; book.chapters)
    {
        a ~= `
    <h2>
    `;
        a ~= book.name;
        a ~= `, Chapter `;
        a ~= (i+1).to!string;
        a ~= `</h2>
        <div class="scripture">
        <p>`;
        foreach (j, v; c.verses)
        {
            if (v.text.length == 0) assert(false, "verse had no text");
            a ~= `
            <span class="verse"><span class="verseid">%s</span>
                %s
            </span>`.format(
                    v.verse,
                    v.text.replace(newParagraphMark, `
            </span>
        </p>
        <p>
            <span class="verse">
                `)
                .replace(newLineMark, `<br />`));
        }
        a ~= `
        </p>`;
    }
    a ~= `
    </div>
  </body>
</html>`;
    ep.Chapter c = {
        title: book.name,
        showInTOC: true,
        content: a.data
    };
    return c;
}
