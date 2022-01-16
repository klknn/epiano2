/**
Epiano2 dplug client.

Copyright: klknn 2022.
License:   MIT, GPL v2 or any later version (See LICENSE).
*/
module epiano2.client;

import std.math;
import dplug.core, dplug.client;
import epiano2.data : epianoData;
import epiano2.parameter : ModParameter;

// This define entry points for plugin formats,
// depending on which version identifiers are defined.
mixin(pluginEntryPoints!Epiano2Client);

enum Param : int {
  envelopeDecay,
  envelopeRelease,
  hardness,
  trebleBoost,
  modulation,
  lfoRate,
  velocitySense,
  stereoWidth,
  polyPhony,
  fineTuning,
  randomTuning,
  overdrive,
}

struct Voice {
  // Sample playback.
  int delta;
  int frac;
  int pos;
  int end;
  int loop;

  // Envelope.
  float env = 0.0f;
  float dec = 0.99f;  // all notes off.

  // First-order LPF.
  float f0;
  float f1;
  float ff;

  float outL;
  float outR;
  int note;
}

struct KeyGroup {
  int root;
  int high;
  int pos;
  int end;
  int loop;
}

class Epiano2Client : Client {
  nothrow @nogc public:

  override PluginInfo buildPluginInfo() const {
    // Plugin info is parsed from plugin.json here at compile time.
    // Indeed it is strongly recommended that you do not fill PluginInfo
    // manually, else the information could diverge.
    static immutable pluginInfo = parsePluginInfo(import("plugin.json"));
    return pluginInfo;
  }

  override Parameter[] buildParameters() const {
    auto params = makeVec!Parameter();

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.envelopeDecay, /*name=*/"Envelope Decay", /*label=*/"",
        /*min=*/0, /*max=*/100, /*defaultValue=*/50);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.envelopeRelease, /*name=*/"Envelope Release",
        /*label=*/"",
        /*min=*/0, /*max=*/100, /*defaultValue=*/50);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.hardness, /*name=*/"Hardness",
        /*label=*/"",
        /*min=*/-50, /*max=*/50, /*defaultValue=*/0);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.trebleBoost, /*name=*/"Treble Boost", /*label=*/"",
        /*min=*/-50, /*max=*/50, /*defaultValue=*/0);

    params ~= mallocNew!ModParameter(
        /*index=*/Param.modulation, /*name=*/"Modulation", /*label=*/"",
        /*min=*/-100, /*max=*/100, /*defaultValue=*/0);

    params ~= mallocNew!LinearFloatParameter(
        /*index=*/Param.lfoRate, /*name=*/"LFO rate", "",
        /*min=*/0.07, /*max=*/36.97, /*defaultValue=*/4.19);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.velocitySense, /*name=*/"Velocity Sense", /*label=*/"",
        /*min=*/0, /*max=*/100, /*defaultValue=*/25);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.stereoWidth, /*name=*/"Stereo Width", /*label=*/"",
        /*min=*/0, /*max=*/200, /*defaultValue=*/100);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.polyPhony, /*name=*/"Polyphony", /*label=*/"",
        /*min=*/0, /*max=*/32, /*defaultValue=*/16);

    params ~= mallocNew!IntegerParameter(
        /*index=*/Param.fineTuning, /*name=*/"Fine Tuning",
        /*label=*/"",
        /*min=*/-50, /*max=*/50, /*defaultValue=*/0);

    params ~= mallocNew!LinearFloatParameter(
        /*index=*/Param.randomTuning, /*name=*/"Random Tuning", "",
        /*min=*/0.0, /*max=*/50.0, /*defaultValue=*/1.1);

    params ~= mallocNew!LinearFloatParameter(
        /*index=*/Param.overdrive, /*name=*/"Overdrive", "",
        /*min=*/0.0, /*max=*/100.0, /*defaultValue=*/0.0);

    return params.releaseData();
  }

  override LegalIO[] buildLegalIO() const {
    auto io = makeVec!LegalIO();
    io ~= LegalIO(/*numInputChannels=*/0, /*numOutputChannels*/1);
    io ~= LegalIO(/*numInputChannels=*/0, /*numOutputChannels*/2);
    return io.releaseData();
  }

  override void reset(
      double sampleRate, int maxFrames, int numInputs, int numOutputs) {
    _sampleRate = sampleRate;
  }

  override void processAudio(
      const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
    // process MIDI - note on/off and similar
    foreach (MidiMessage msg; getNextMidiMessages(frames)) {
      // if (msg.isNoteOn) _synth.markNoteOn(msg.noteNumber());
      // else if (msg.isNoteOff) _synth.markNoteOff(msg.noteNumber());
      // else if (msg.isAllNotesOff || msg.isAllSoundsOff)
      //   _synth.markAllNotesOff();
    }

    // foreach (ref sample; outputs[0][0 .. frames])
    //   sample = _synth.nextSample();
    outputs[0][0 .. frames] = 0f;
    outputs[1][0 .. frames] = 0f;

    // Copy output to every channel
    // foreach (chan; 1 .. outputs.length)
    //   outputs[chan][0 .. frames] = outputs[0][0 .. frames];
  }

  void readAllParams() {}

 private:

  // Global internal variables
  shared static immutable KeyGroup[34] keyGroups;
  shared static immutable short[epianoData.length] waves;

  enum EVENTBUFFER = 120;
  enum EVENTS_DONE = 99999999;
  int[EVENTBUFFER + 8] notes_ = [EVENTS_DONE];
  Voice[32] _voices;
  float _sampleRate = 44100;
  float _volume = 0.2;
  float _muff = 160; // What is this?
  int _size;
  int _sustain;
  int _activeVoices;

  float tl = 0;
  float tr = 0;
  float lfo0 = 0;
  float dlfo = 0;
  float lfo1 = 1;

  shared static this() {
    //Waveform data and keymapping
    keyGroups[ 0].root = 36;  keyGroups[ 0].high = 39; //C1
    keyGroups[ 3].root = 43;  keyGroups[ 3].high = 45; //G1
    keyGroups[ 6].root = 48;  keyGroups[ 6].high = 51; //C2
    keyGroups[ 9].root = 55;  keyGroups[ 9].high = 57; //G2
    keyGroups[12].root = 60;  keyGroups[12].high = 63; //C3
    keyGroups[15].root = 67;  keyGroups[15].high = 69; //G3
    keyGroups[18].root = 72;  keyGroups[18].high = 75; //C4
    keyGroups[21].root = 79;  keyGroups[21].high = 81; //G4
    keyGroups[24].root = 84;  keyGroups[24].high = 87; //C5
    keyGroups[27].root = 91;  keyGroups[27].high = 93; //G5
    keyGroups[30].root = 96;  keyGroups[30].high =999; //C6

    keyGroups[0].pos = 0;        keyGroups[0].end = 8476;     keyGroups[0].loop = 4400;
    keyGroups[1].pos = 8477;     keyGroups[1].end = 16248;    keyGroups[1].loop = 4903;
    keyGroups[2].pos = 16249;    keyGroups[2].end = 34565;    keyGroups[2].loop = 6398;
    keyGroups[3].pos = 34566;    keyGroups[3].end = 41384;    keyGroups[3].loop = 3938;
    keyGroups[4].pos = 41385;    keyGroups[4].end = 45760;    keyGroups[4].loop = 1633; //was 1636;
    keyGroups[5].pos = 45761;    keyGroups[5].end = 65211;    keyGroups[5].loop = 5245;
    keyGroups[6].pos = 65212;    keyGroups[6].end = 72897;    keyGroups[6].loop = 2937;
    keyGroups[7].pos = 72898;    keyGroups[7].end = 78626;    keyGroups[7].loop = 2203; //was 2204;
    keyGroups[8].pos = 78627;    keyGroups[8].end = 100387;   keyGroups[8].loop = 6368;
    keyGroups[9].pos = 100388;   keyGroups[9].end = 116297;   keyGroups[9].loop = 10452;
    keyGroups[10].pos = 116298;  keyGroups[10].end = 127661;  keyGroups[10].loop = 5217; //was 5220;
    keyGroups[11].pos = 127662;  keyGroups[11].end = 144113;  keyGroups[11].loop = 3099;
    keyGroups[12].pos = 144114;  keyGroups[12].end = 152863;  keyGroups[12].loop = 4284;
    keyGroups[13].pos = 152864;  keyGroups[13].end = 173107;  keyGroups[13].loop = 3916;
    keyGroups[14].pos = 173108;  keyGroups[14].end = 192734;  keyGroups[14].loop = 2937;
    keyGroups[15].pos = 192735;  keyGroups[15].end = 204598;  keyGroups[15].loop = 4732;
    keyGroups[16].pos = 204599;  keyGroups[16].end = 218995;  keyGroups[16].loop = 4733;
    keyGroups[17].pos = 218996;  keyGroups[17].end = 233801;  keyGroups[17].loop = 2285;
    keyGroups[18].pos = 233802;  keyGroups[18].end = 248011;  keyGroups[18].loop = 4098;
    keyGroups[19].pos = 248012;  keyGroups[19].end = 265287;  keyGroups[19].loop = 4099;
    keyGroups[20].pos = 265288;  keyGroups[20].end = 282255;  keyGroups[20].loop = 3609;
    keyGroups[21].pos = 282256;  keyGroups[21].end = 293776;  keyGroups[21].loop = 2446;
    keyGroups[22].pos = 293777;  keyGroups[22].end = 312566;  keyGroups[22].loop = 6278;
    keyGroups[23].pos = 312567;  keyGroups[23].end = 330200;  keyGroups[23].loop = 2283;
    keyGroups[24].pos = 330201;  keyGroups[24].end = 348889;  keyGroups[24].loop = 2689;
    keyGroups[25].pos = 348890;  keyGroups[25].end = 365675;  keyGroups[25].loop = 4370;
    keyGroups[26].pos = 365676;  keyGroups[26].end = 383661;  keyGroups[26].loop = 5225;
    keyGroups[27].pos = 383662;  keyGroups[27].end = 393372;  keyGroups[27].loop = 2811;
    keyGroups[28].pos = 383662;  keyGroups[28].end = 393372;  keyGroups[28].loop = 2811; //ghost
    keyGroups[29].pos = 393373;  keyGroups[29].end = 406045;  keyGroups[29].loop = 4522;
    keyGroups[30].pos = 406046;  keyGroups[30].end = 414486;  keyGroups[30].loop = 2306;
    keyGroups[31].pos = 406046;  keyGroups[31].end = 414486;  keyGroups[31].loop = 2306; //ghost
    keyGroups[32].pos = 414487;  keyGroups[32].end = 422408;  keyGroups[32].loop = 2169;

    // Extra xfade loop.
    waves = epianoData;
    foreach (k; 0 .. 28) {
      int p0 = keyGroups[k].end;
      int p1 = keyGroups[k].end - keyGroups[k].loop;
      for (float xf = 1.0; xf > 0.0; xf += -0.02) {
        waves[p0] = cast(short)((1.0f - xf) * cast(float) waves[p0] +
                                xf * cast(float) waves[p1]);
        p0--;
        p1--;
      }
    }
  }
}
