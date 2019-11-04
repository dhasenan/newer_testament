module nt.pipeline;

import jsonizer;
import markov;
import nt.build;
import nt.config;
import std.file;
import std.path;
import std.stdio;

Pipeline buildPipeline(Config config)
{
    auto resources = new Resources;
    Stage[] stages;
    foreach (input; config.inputs)
    {
        // Register the base input file
        auto source = absolutePath(input.source, config.basedir);
        resources.addInput(input.source, source);

        // Register the adapter
        Stage s;
        switch (input.type)
        {
            case "kjv":
                s = new KjvInputStage(input.source);
                break;
            case "bom":
                s = new BookOfMormonInputStage(input.source);
                break;
            default:
                throw new Exception("unrecognized input type " ~ input.type);
        }

        // Build the standard processors on top of that input
        auto processors = processSource(input, s);
        stages ~= processors;
    }

    string[] sections;
    foreach (section; config.sections)
    {
        if (section.thesaurus)
        {
            auto source = absolutePath(section.thesaurus.database, config.basedir);
            resources.addInput(section.thesaurus.database, source);
        }

        auto genSkeleton = new GenerateSkeleton(section.input, section.size, section.name);
        auto inflateVerses = new InflateVerses(genSkeleton.output, section.input, section.name);
        auto thesaurus = new ApplyThesaurus(inflateVerses.output, section.thesaurus, section.name);
        auto updateCharacters = new UpdateCharacters(thesaurus.output, section.name);
        stages ~= [genSkeleton, inflateVerses, thesaurus, updateCharacters];
        sections ~= updateCharacters;
    }
    stages ~= new CombineSections(sections, config.name);
    stages ~= new ToEpub(config.name, config.output);
}

Stage[] processSource(InputConfig input, Stage makeJson)
{
    Stage nameList = new ListNames(input.source, makeJson.output);
    Stage nameAnonymized = new AnonymizeNames(input.source, nameList.output);
    Stage nameChain = new BuildNameChain(input.source, input.names, nameList.output);
    Stage themeCatalogue = new ThemeCatalogue(input.source, input.themes, makeJson.output);
    Stage themesOnly = new ThemesOnly(input.source, makeJson.output, themeCatalogue.output);
    Stage verseChain = new VerseChain(input.source, input.verseContext, themesOnly.output);
    return [
        nameAnonymized,
        nameList,
        nameChain,
        themeCatalogue,
        themesOnly,
        verseChain
    ];
}
