# Isobaric interference corrections.
#
# An isobaric interference is a second element contributing signal at the mass
# used to measure the target isotope: at mass 176, `Hf176` is overlapped by
# `Lu176` and `Yb176`. KJ corrects for it by measuring an interference-free
# isotope of the interfering element (the *proxy*), scaling by the natural
# isotopic ratio, and subtracting:
#
#     signal_corrected = signal_176 - (proxy_signal - blank) * iratio(ion, proxy) * massbias
#
# This mirrors the flow KJ's TUI drives (`TUI.jl`, states `addInterference` →
# `interferenceType` → `interferenceIon` → `interferenceProxyChannel`): the
# target is one of the P/D/d pairings, the correction is either poly- or
# mono-isotopic, and for the poly case the user picks the *channel* the proxy
# is measured on while KJ derives the proxy isotope from it via
# `channel2proxy`. An explicit proxy is only asked for when that derivation
# fails, which is KJ's `setInterferenceProxy` state.
#
# KJ does not validate any of this: a wrong pairing produces a
# plausible-looking number rather than an error. The panel therefore reports
# the applied ratio and any suspect pairing instead of restricting the
# choices, which would diverge from the TUI.

"""
Reference isotopic ratios parsed from the IsoplotR constants KJ bundles in
`KJ.jsonTemplate()`, keyed `"<num><den>"` e.g. `"Lu176Lu175"`.

This is a second, independent copy of the same constants that
`KJ.iratio` reads from `settings/iratio.csv`, so the two can be compared —
see [`ratio_check`](@ref).
"""
const REFERENCE_IRATIOS = let out = Dict{String,Float64}()
    # Matched without relying on how the template quotes its keys: an entry is
    # two stacked nuclides followed by `[value,error]`. The `lambda` and
    # `imass` sections key on a single nuclide (`U238`, `Re185`), so they
    # cannot match this pattern and no section-slicing is needed.
    #
    # `test/runtests.jl` asserts a known set of ratios parses, so a change to
    # KJ's template shows up as a test failure rather than as a cross-check
    # that has quietly stopped checking.
    for m in eachmatch(r"([A-Z][a-z]?\d+[A-Z][a-z]?\d+)[^\[]{1,4}\[\s*([0-9.eE+-]+)",
                       KJ.jsonTemplate())
        out[m.captures[1]] = parse(Float64, m.captures[2])
    end
    out
end

"""
The three pairings a `KJ.Gmethod` corrects, in the order KJ's
`TUIchooseInterferenceTarget!` lists them.
"""
const INTERFERENCE_ROLES = (:P, :D, :d)

"The pairing `role` names on `method`."
role_pairing(method::KJ.Gmethod, role::Symbol) =
    role === :P ? method.P : role === :D ? method.D : method.d

"Mass number of a nuclide label, e.g. `\"Lu176\"` → `176`. `nothing` if absent."
function nuclide_mass(nuclide::AbstractString)
    m = match(r"\d+", nuclide)
    return isnothing(m) ? nothing : parse(Int, m.match)
end

"""
Isotopes that interfere with `target` — same nominal mass, different element.
`\"Hf176\"` → `[\"Yb176\", \"Lu176\"]`. This is the list KJ's `interferenceIon`
state offers.
"""
interference_candidates(target::AbstractString) = KJ.TUIgetInterferences(target)

"Isotope KJ reads `channel` as measuring, or `nothing` when it cannot tell."
derive_proxy(channel::AbstractString) = KJ.channel2proxy(channel)

"""
Isotopes offered when [`derive_proxy`](@ref) returns `nothing`: every isotope
of the interfering element, matching what KJ's `setInterferenceProxy` state
lists.
"""
proxy_candidates(ion::AbstractString) = KJ.TUIions2isotopes([ion])

"Reference value for `num/den` from [`REFERENCE_IRATIOS`], or `nothing`."
function reference_ratio(num::AbstractString, den::AbstractString)
    haskey(REFERENCE_IRATIOS, num * den) && return REFERENCE_IRATIOS[num * den]
    haskey(REFERENCE_IRATIOS, den * num) && return 1 / REFERENCE_IRATIOS[den * num]
    return nothing
end

"""
Compare the ratio KJ will apply against the bundled reference value.

Returns `(status, applied, reference)` where status is
`:ok` (agree), `:mismatch` (differ by more than `rtol`), `:unchecked` (no
reference available) or `:invalid` (KJ has no ratio for the pair).

A `:mismatch` means `settings/iratio.csv` disagrees with the IsoplotR
constants — the correction will be wrong by `applied / reference`.
"""
function ratio_check(ion::AbstractString, proxy::AbstractString; rtol = 1.0e-3)
    applied = KJ.iratio(ion, proxy)
    reference = reference_ratio(ion, proxy)
    isnothing(applied) && return (:invalid, nothing, reference)
    isnothing(reference) && return (:unchecked, applied, nothing)
    agrees = isapprox(applied, reference; rtol = rtol)
    return (agrees ? :ok : :mismatch, applied, reference)
end

"""
Detected mass of a channel label like `"Hf176 -> 258"` → `258`, i.e. the mass
the ion is counted at after any reaction-cell shift. `nothing` if the label
carries no `-> mass` part.
"""
function channel_detected_mass(channel::AbstractString)
    m = match(r"->\s*(\d+)", channel)
    return isnothing(m) ? nothing : parse(Int, m.captures[1])
end

"""
Reaction-cell mass shift of a channel: detected mass − nuclide mass. An
on-mass channel shifts by 0, `"Lu175 -> 257"` by 82.
"""
function channel_mass_shift(channel::AbstractString)
    detected = channel_detected_mass(channel)
    isnothing(detected) && return nothing
    nuclide = nuclide_mass(channel)
    isnothing(nuclide) && return nothing
    return detected - nuclide
end

"""
Channels that could measure a proxy for `ion`: those KJ reads as a *different*
isotope of the same element. Scaling by `iratio(ion, proxy)` is only a natural
abundance ratio within one element, so nothing else can be correct.
"""
function plausible_proxy_channels(ion::AbstractString, channels)
    element = KJ.channel2element(ion)
    isnothing(element) && return String[]
    mass = nuclide_mass(ion)
    return filter(channels) do c
        proxy = derive_proxy(c)
        isnothing(proxy) && return false
        return KJ.channel2element(proxy) == element && nuclide_mass(proxy) != mass
    end
end

"""
Every channel, ordered with the plausible proxy channels for `ion` first.

The menu offers all of them, as KJ's TUI does. The order only decides which
are visible without scrolling, and a run has far more channels than a
dropdown shows at once.
"""
function proxy_channel_options(ion::AbstractString, channels)
    plausible = plausible_proxy_channels(ion, channels)
    return vcat(plausible, filter(!in(plausible), channels))
end

"""
Default channel to measure the `ion` proxy on, for a target measured on
`target_channel`.

Among the plausible channels, prefers one whose reaction-cell mass shift
matches the target's: signal that reached the detector through a different
pathway sits on a different intensity scale, so pairing an on-mass proxy with
a mass-shifted target over-subtracts by orders of magnitude. For Lu-Hf this
picks `Lu175 -> 257` over the on-mass `Lu175 -> 175` for a `Hf176 -> 258`
target, which is the pairing KJ's own test uses.
"""
function default_proxy_channel(ion::AbstractString, target_channel::AbstractString,
                               channels)
    usable = plausible_proxy_channels(ion, channels)
    isempty(usable) && return ""
    shift = channel_mass_shift(target_channel)
    if !isnothing(shift)
        i = findfirst(c -> channel_mass_shift(c) == shift, usable)
        isnothing(i) || return usable[i]
    end
    return first(usable)
end

"One interference correction configured against a P/D/d pairing."
abstract type AbstractInterferenceSpec end

"""
Poly-isotopic correction: subtract `ion` from the target by measuring `proxy`
on `channel` and scaling by `iratio(ion, proxy)`.

`proxy` is normally [`derive_proxy`](@ref) of `channel` and is empty when KJ
could not derive one — the case the panel asks the user to resolve.
"""
struct InterferenceSpec <: AbstractInterferenceSpec
    ion::String
    proxy::String
    channel::String
end

"""
Poly correction with the proxy derived from `channel`, as the TUI does.

`channel` is a keyword so this cannot be confused with the three-field
constructor, whose second positional argument is the *proxy*.
"""
InterferenceSpec(ion::AbstractString; channel::AbstractString) =
    InterferenceSpec(ion, something(derive_proxy(channel), ""), channel)

"""
Mono-isotopic correction: the interfering oxide is measured on `channel` (X in
KJ's notation) and corrected as `X × YO / Y`, where Y is a non-interfering rare
earth with known abundance relative to X. `metal` is the Y channel, `oxide` the
YO channel, and `standards` names the sample groups the oxide production rate
is fitted on.
"""
struct MonoInterferenceSpec <: AbstractInterferenceSpec
    channel::String
    metal::String
    oxide::String
    standards::Vector{String}
end

MonoInterferenceSpec(; channel = "", metal = "", oxide = "", standards = String[]) =
    MonoInterferenceSpec(channel, metal, oxide, collect(standards))

"Key this correction is stored under in `Pairing.interferences`."
interference_key(spec::InterferenceSpec) = spec.ion
interference_key(spec::MonoInterferenceSpec) = spec.channel

KJ.Interference(spec::InterferenceSpec) =
    KJ.Interference(proxy = spec.proxy, channel = spec.channel)

KJ.MonoInterference(spec::MonoInterferenceSpec) =
    KJ.MonoInterference(metal = spec.metal, oxide = spec.oxide,
                        standards = Set(spec.standards))

"The `KJ.AbstractInterference` that `spec` describes."
interference(spec::InterferenceSpec) = KJ.Interference(spec)
interference(spec::MonoInterferenceSpec) = KJ.MonoInterference(spec)

"""
Why `spec` cannot be used as configured, or `nothing` if it can.

`target_channel` is the channel the corrected isotope is measured on, needed
to compare reaction-cell mass shifts.
"""
function interference_problem(spec::InterferenceSpec, target_channel::AbstractString,
                              channels)
    isempty(spec.channel) && return "no proxy channel selected"
    spec.channel in channels ||
        return "$(spec.channel) is not a channel in this run"
    isempty(spec.proxy) &&
        return "KJ cannot tell which isotope $(spec.channel) measures — pick it below"
    element = KJ.channel2element(spec.ion)
    if KJ.channel2element(spec.proxy) != element
        return "$(spec.channel) measures $(spec.proxy), not $element; the " *
               "correction scales by $(spec.ion)/$(spec.proxy), which is only a " *
               "natural abundance ratio within one element"
    end
    spec.ion == spec.proxy &&
        return "$(spec.channel) measures $(spec.ion) itself, which is the signal " *
               "being corrected for"
    status, applied, _ = ratio_check(spec.ion, spec.proxy)
    status === :invalid && return "no isotopic ratio known for $(spec.ion)/$(spec.proxy)"
    (isfinite(applied) && applied > 0) ||
        return "isotopic ratio for $(spec.ion)/$(spec.proxy) is not a positive number"
    shift = channel_mass_shift(spec.channel)
    target_shift = channel_mass_shift(target_channel)
    if !isnothing(shift) && !isnothing(target_shift) && shift != target_shift
        return "mass shift $shift, but the target is measured at $target_shift. " *
               "Signal from different reaction pathways is not on a comparable scale."
    end
    return nothing
end

function interference_problem(spec::MonoInterferenceSpec, ::AbstractString, channels)
    isempty(spec.channel) && return "no interfering channel (X) selected"
    isempty(spec.metal) && return "no metal channel (Y) selected"
    isempty(spec.oxide) && return "no oxide channel (YO) selected"
    for (role, c) in (("interfering (X)", spec.channel), ("metal (Y)", spec.metal),
                      ("oxide (YO)", spec.oxide))
        c in channels || return "$role channel $c is not in this run"
    end
    isempty(spec.standards) &&
        return "no calibration groups selected — KJ fits the oxide production " *
               "rate on these"
    return nothing
end

"""
Whether `spec` is fully configured and names only channels the run actually
has.

Two kinds of row are held in panel state but kept out of the method: one the
user has not finished filling in, and one left pointing at a channel a
later-loaded run does not have. [`interference_problem`](@ref) reports both,
and applying either would hand `process!` a pairing it cannot resolve.
"""
is_applicable(spec::InterferenceSpec, channels) =
    !isempty(spec.ion) && !isempty(spec.proxy) && spec.channel in channels

# Standards are required because KJ fits the oxide production rate on them;
# the TUI likewise always routes a mono interference through its "glass" step.
is_applicable(spec::MonoInterferenceSpec, channels) =
    spec.channel in channels && spec.metal in channels &&
    spec.oxide in channels && !isempty(spec.standards)

"""
Apply the applicable `specs` to `pairing.interferences`, keyed as KJ keys
them: by interfering isotope for poly corrections, by interfering channel for
mono. `channels` is the run's channel list, against which each spec is checked
by [`is_applicable`](@ref).

Called from `build_method` on every rebuild, since the method is
reconstructed from scratch whenever a channel or proxy changes and
interferences would otherwise be silently dropped.
"""
function apply_interferences!(pairing::KJ.Pairing, specs, channels)
    for spec in specs
        is_applicable(spec, channels) || continue
        pairing.interferences[interference_key(spec)] = interference(spec)
    end
    return pairing
end
