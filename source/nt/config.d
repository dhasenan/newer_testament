/** Configuration for a bible, both learning and generation. */
module nt.config;

import jsonizer;

/*
Example config for a New Testament composed of a few gospels, a number of epistles, and a bit of
prophecy:

{
  "name": "Purple New Testament",
  "intermediateDir": "intermediate",
  "output": "PurpleNewTestament.epub",
  "inputs": [
    {
        "type": "kjv",
        "source": "gospels.txt",
        "themeFrequency": {"min": 10, "max": 100},
        "nameContext": {"min": 1, "max": 3},
        "verseContext": {"min": 1, "max": 3}
    },
    {
        "type": "kjv",
        "source": "epistles.txt",
        "themeFrequency": {"min": 10, "max": 100},
        "nameContext": {"min": 1, "max": 3},
        "verseContext": {"min": 1, "max": 3}
    },
    {
        "type": "niv",
        "source": "prophecy.txt",
        "themeFrequency": {"min": 15, "max": 400},
        "nameContext": {"min": 1, "max": 3},
        "verseContext": {"min": 1, "max": 3}
    },
  ],
  "sections": [
    {
      "name": "gospels",
      "input": "gospels.txt",
      "characters": {
        "chapterRatio": 1.4,
        "bookRatio": 2.5
      },
      "thesaurus": {
        "database": "dict.sqlite3",
        "factor": 0.2
      },
      "size": {
        "books": {"min": 2, "max": 5},
        "chapters": {"min": 5, "max": 20},
        "verses": {"min": 12, "max": 50}
      }
    },
    {
      "name": "epistles",
      "input": "epistles.txt",
      "characters": {
        "chapterRatio": 1.4,
        "bookRatio": 2.5
      },
      "thesaurus": {
        "database": "dict.sqlite3",
        "factor": 0.3
      },
      "size": {
        "books": {"min": 5, "max": 15},
        "chapters": {"min": 5, "max": 10},
        "verses": {"min": 12, "max": 40}
      }
    },
    {
      "name": "prophecy",
      "inputs": ["prophecy.txt"],
      "characters": {
        "chapterRatio": 1.4,
        "bookRatio": 2.5
      },
      "thesaurus": {
        "database": "dict.sqlite3",
        "factor": 0.3
      },
      "size": {
        "books": {"min": 1, "max": 3},
        "chapters": {"min": 5, "max": 20},
        "verses": {"min": 20, "max": 50}
      }
    }
  ]
}
*/
class Config
{
    string path, basedir;

    mixin JsonizeMe;
    @jsonize
    {
        string name;
        string intermediateDir = "intermediate";
        string output;
        SectionConfig[] sections;
    }

    static Config fromFile(string path)
    {
        static import std.path;

        auto c = readJSON!Config(path);

        // Fix up all the relative paths into absolute paths
        c.path = path;
        c.basedir = std.path.absolutePath(std.path.baseDir(path));
        c.intermediateDir = std.path.absolutePath(c.intermediateDir, c.basedir);
        if (c.output == "")
        {
            c.output = std.path.buildPath(c.basedir, c.name ~ ".epub");
        }
        else
        {
            c.output = std.path.absolutePath(c.basedir);
        }

        return c;
    }
}

class InputConfig
{
    mixin JsonizeMe;
    @jsonize
    {
        string type;
        string source;
        Interval themeFrequency = Interval(20, 1000);
        Interval nameContext = Interval(1, 3);
        Interval verseContext = Interval(1, 3);
    }
}

class SectionConfig
{
    mixin JsonizeMe;
    @jsonize
    {
        string input;
        CharacterConfig characters;
        ThesaurusConfig thesaurus;
        SizeConfig size;
    }
}

struct ThesaurusConfig
{
    mixin JsonizeMe;
    @jsonize
    {
        string database;
        double factor = 0.2;
    }
}

struct SizeConfig
{
    mixin JsonizeMe;
    @jsonize
    {
        Interval chapters = Interval(5, 50);
        Interval books = Interval(15, 50);
        Interval verses = Interval(12, 150);
    }
}

struct Interval
{
    this(string s)
    {
        import std.algorithm, std.conv;
        auto p = s.splitter("-");
        min = p.front.to!uint;
        p.popFront;
        if (p.empty)
            max = min;
        else
            max = p.front.to!uint;
    }

    mixin JsonizeMe;
    @jsonise uint min, max;

    uint uniform()
    {
        import std.random : uniform;
        return uniform(min, max + 1);
    }

    uint uniform(TRng)(ref TRng rand)
    {
        import std.random : uniform;
        return uniform(min, max + 1, rand);
    }

    size_t[] all()
    {
        import std.range : iota;
        import std.array : array;
        return iota(cast(size_t)min, cast(size_t)max+1).array;
    }
}

