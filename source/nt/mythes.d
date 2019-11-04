/** Handler for the MyThes file format */
module nt.mythes;

import std.string;
import std.algorithm;

class Mythes
{
    private string[][string] _synonyms;

    Mythes read(T)(string path, T[string] words)
    {
        bool canAdd = false;
        string term;
        string[] related;
        foreach (i, line; File(path, "r").byLineCopy)
        {
            if (!line.length) break;
            if (line[0] != '(')
            {
                if (canAdd)
                {
                    _synonyms[term] = related;
                }
                term = line.splitter('|').front;
                related = [];
                canAdd = !!(term in words);
                continue;
            }
            if (!canAdd) continue;
            foreach (part; line.splitter('|'))
            {
                if (part.canFind("ordinal") || part.canFind("cardinal"))
                {
                    canAdd = false;
                    break;
                }
                if (part.canFind('('))
                {
                    continue;
                }
                related ~= part;
            }
        }
        return this;
    }

    string[] synonyms(string term)
    {
        if (auto p = term.toLower in _synonyms)
        {
            return *p;
        }
        return null;
    }
}
