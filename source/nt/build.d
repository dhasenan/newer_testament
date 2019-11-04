module nt.build;

import jsonizer;
import markov;
import nt.config;
import std.file;
import std.path;
import std.stdio;

struct Artifact
{
    string rule;
    string tag;

    static Artifact parse(string str)
    {
        import std.string;
        auto s = str.indexOf(':');
        if (s < 0)
        {
            return Artifact("output", str);
        }
        return Artifact(str[0 .. s], str[s + 1 .. $]);
    }

    string toString() const
    {
        return rule ~ ":" ~ tag;
    }

    int opCmp(const ref Artifact other) const
    {
        import std.uni;
        auto i = icmp(rule, other.rule);
        if (i != 0) return i;
        return icmp(tag, other.tag);
    }
}

interface Stage
{
    /// input rules (for the same tag)
    string[] input();
    /// rule that this thing generates
    string output();
    void perform(Resources resources, string tag);
}

struct Name { string name; }

class TransformStage(alias fn) : Stage
{
    static this()
    {
        static if (is(typeof(fn) params == __parameters))
        {
            _inputs.length = params.length;
            static foreach (i, p; params)
            {
                static foreach (tag; getUDAs!(p, Name))
                {
                    _inputs[i] = tag.name;
                }
            }
        }
        static foreach (tag; getUDAs!(p, Name))
        {
            _output = tag.name;
        }
    }

    static string[] _inputs;
    static string _outputs;

    string[] inputs() { return _inputs; }
    string[] outputs() { return _outputs; }

    void perform(Resources resources, string tag)
    {
        static if (is(typeof(fn) params == __parameters))
        {
            typeof(params) args;
            static foreach (i, p; params)
            {
                args[i] = resources.load!(typeof(p))(Artifact(_inputs[i], tag));
            }
        }
        auto result = fn(args);
        resources.store(Artifact(_output, tag), result);
    }
}

class Pipeline
{
    private Resources resources;
    private Stage[string] byOutput;

    this(Resources resources, Stage[] stages)
    {
        this.resources = resources;
        foreach (s; stages)
        {
            assert(!(s in byOutput), "stage " ~ s.output ~ " added multiple times");
            byOutput[s.output] = s;
        }
    }

    void buildAll()
    {
        foreach (k, v; byOutput)
        {
            _build(v, false);
        }
    }

    void rebuildAll()
    {
        foreach (k, v; byOutput)
        {
            _build(v, true);
        }
    }

    void build(string target)
    {
        auto stage = target in stages;
        if (!stage)
        {
            throw new Exception("No such stage: " ~ target);
        }
        if (!_build(*stage))
        {
            tracef("%s is up to date", target);
        }
    }

    void rebuild(string target)
    {
        auto stage = target in stages;
        if (!stage)
        {
            throw new Exception("No such stage: " ~ target);
        }
        _build(stage, true);
    }

    private bool _build(Stage stage, bool force = false)
    {
        // I need to build this stage if any of my child stages need to be built, or if any of my
        // inputs are older than my output.
        auto last = resources.age(stage.output);
        bool needsBuild = last.isNull || force;
        foreach (s; stage.inputs)
        {
            if (auto t = s in stages)
            {
                auto builtThisChild = _build(*t, force);
                needsBuild |= builtThisChild;
            }
            if (!needsBuild)
            {
                auto depAge = resources.age(s);
                if (depAge.isNull)
                {
                    throw new Exception("failed to build " ~ s ~ ", needed by " ~ stage.name);
                }
                // The dependency doesn't exist or it's newer than the current file.
                needsBuild = depAge > last;
            }
        }

        if (needsBuild)
        {
            tracef("building %s", stage.output);
            stage.perform(resources);
            tracef("built %s", stage.output);
        }
    }
}

class Resources
{
    private Config config;
    private string intermediateDir;
    private string[string] inputs;
    private SysTime[string] date;

    this(Config config)
    {
        this.config = config;
        this.intermediateDir = absolutePath(config.intermediateDir, config.path);

        foreach (section; config.sections)
        {
            foreach (input; config.inputs)
            {
                auto inputPath = absolutePath(input, config.path);
                inputs[input] = inputPath;
            }
        }
    }

    T load(T)(string name)
    {
        static if (is(T == string))
        {
            return mmap(name);
        }
        else static if (is(typeof(fromJSONString!T(""))))
        {
            return readJSON!T(filename(name, "json"));
        }
        else static if is(T : MarkovChain!string)
        {
            return decodeBinary!string(File(filename(name, "chain"), "r"))
        }
        else
        {
            static assert(false, "can't load objects of type " ~ T.stringof);
        }
    }

    void store(T)(string name, T value)
    {
        date[name] = Clock.currTime;;
        static if (is(T == string))
        {
            auto f = File(filename(name, extension), "w");
            f.write(value);
            f.close;
        }
        else static if (is(typeof(fromJSONString!T(""))))
        {
            writeJSON!T(filename(name, "json"));
        }
        else static if is(T : MarkovChain!string)
        {
            encodeBinary!string(File(filename(name, "chain"), "w"))
        }
        else
        {
            static assert(false, "can't store objects of type " ~ T.stringof);
        }
    }

    Nullable!SysTime age(string name)
    {
        if (auto p = name in date)
        {
            return nullable(*p);
        }

        Nullable!SysTime modified;
        foreach (i, e; dirEntries(intermediateDir, name ~ "*", SpanMode.shallow, false).enumerate)
        {
            if (!e.isFile) continue;
            if (name != baseName(e.name) && stripExtension(baseName(e.name)) != name) continue;
            if (modified.isNull)
                modified = nullable(e.timeLastModified);
            else
                throw new Exception("multiple possible resources named " ~ name);
        }
        if (!modified.isNull)
            this.date[name] = modified.get;
        return modified;
    }

    string filename(string name, string extension)
    {
        if (auto i = name in inputs)
        {
            return *i;
        }
        return buildPath(intermediateDir, name ~ "." ~ extension);
    }
}

