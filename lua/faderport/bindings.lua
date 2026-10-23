--[[-----------------------------------------------------------------------------------

  FaderPort DSP bindings (user editable)

  In DSP mode (bank button) fader and pan are bound to a pair of FX parameters.
  Left/right iterate over the pairs, shift+left/right select the previous/next FX.

  match : case insensitive plain substring of the FX name (e.g. "ReaComp" matches
          "VST: ReaComp (Cockos)"). The original FX name is used, renaming in the
          FX chain doesn't break a binding. First match wins.
  pairs : list of { fader, pan }. Each entry is either
            - a number : 1-based parameter index (as shown by the action
                         "Airmann FaderPort - Show FX parameters")
            - a string : case insensitive prefix of the parameter name
            - 0        : nothing is bound
          Unresolvable entries are treated as 0, a pair with nothing bound is skipped.

  IMPORTANT HINT (taken over from the Renoise driver)
  the order/focus of the bindings is laid on (final) mixing and not creative sound
  design. Means: level and stereo parameters like wet/gain/pan/width are usually
  the first binding pairs.

  FX without an entry: if generic_fallback is true, the parameters are bound
  pairwise in their natural order (1,2), (3,4), ...

-------------------------------------------------------------------------------------]]

return {

  generic_fallback = true,

  fx = {

    --------------------- REAPER STOCK PLUGINS -------------------------
    -- TODO verify parameter names with "Show FX parameters" for your REAPER version

    -- 4-band default layout: per band freq, gain, q
    { match = "ReaEQ", pairs = { { 2, 1 }, { 5, 4 }, { 8, 7 }, { 11, 10 }, { 3, 6 }, { 9, 12 } } },

    { match = "ReaComp", pairs = { { "Thresh", "Ratio" }, { "Attack", "Release" },
                                   { "Wet", "Dry" }, { "Knee", "Pre-comp" } } },

    { match = "ReaXcomp", pairs = { { "Wet", "Dry" } } },

    { match = "ReaGate", pairs = { { "Thresh", "Hold" }, { "Attack", "Release" }, { "Wet", "Dry" } } },

    { match = "ReaLimit", pairs = { { "Threshold", "Ceiling" } } },

    { match = "ReaDelay", pairs = { { "Wet", "Dry" } } },

    { match = "ReaVerbate", pairs = { { "Wet", "Dry" }, { "Room size", "Dampening" },
                                      { "Stereo width", "Initial delay" } } },

    { match = "ReaVerb", pairs = { { "Wet", "Dry" } } },

    { match = "ReaFIR", pairs = { { "Gain", 0 } } },

    --------------------------- 3RD PARTY -----------------------------

    -- Voxengo (indices taken over from the Renoise driver)
    { match = "Elephant", pairs = { { 3, 4 } } }, -- in, out
    { match = "Polysquasher", pairs = { { 5, 1 }, { 3, 4 }, { 2, 2 } } }, -- output/bypass, threshold/ratio, oversample
  },
}
