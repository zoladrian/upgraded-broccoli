class_name SpeechPipeline
extends RefCounted

const DEFAULT_DATABASE_PATH := "res://assets/phonemes_pl.json"
const DIACRITIC_FOLD := {
    "ą": "a",
    "ć": "c",
    "ę": "e",
    "ł": "l",
    "ń": "n",
    "ó": "o",
    "ś": "s",
    "ź": "z",
    "ż": "z"
}

var _phoneme_db: Dictionary = {}
var _grapheme_map: Dictionary = {}
var _digraph_map: Dictionary = {}
var _substitution_map: Dictionary = {}
var _key_weight_map: Dictionary = {}
var _phoneme_to_letters: Dictionary = {}

var _non_letter_regex := RegEx.new()
var _multi_space_regex := RegEx.new()

func _init(database_path: String = DEFAULT_DATABASE_PATH) -> void:
    _phoneme_db = _load_database(database_path)
    _grapheme_map = _phoneme_db.get("graphemes", {})
    _digraph_map = _phoneme_db.get("digraphs", {})
    _substitution_map = _phoneme_db.get("substitutions", {})
    _key_weight_map = _phoneme_db.get("key_weights", {})
    _phoneme_to_letters = _phoneme_db.get("phoneme_to_letters", {})

    _non_letter_regex.compile("[^a-ząćęłńóśźż0-9\\s]")
    _multi_space_regex.compile("\\s+")

func normalize_text(text: String) -> String:
    var lowered := text.strip_edges().to_lower()
    lowered = _non_letter_regex.sub(lowered, " ")
    lowered = _multi_space_regex.sub(lowered, " ")
    return lowered.strip_edges()

func fold_to_ascii(text: String) -> String:
    var result := text
    for key in DIACRITIC_FOLD.keys():
        result = result.replace(key, DIACRITIC_FOLD[key])
    return result

func evaluate(observed_text: String, target_text: String, context: Dictionary = {}) -> Dictionary:
    var normalized_input := normalize_text(observed_text)
    var normalized_target := normalize_text(target_text)
    var folded_input := fold_to_ascii(normalized_input)
    var folded_target := fold_to_ascii(normalized_target)

    var evaluation := {
        "normalized_input": normalized_input,
        "normalized_target": normalized_target,
        "folded_input": folded_input,
        "folded_target": folded_target,
        "text_distance": 0,
        "text_similarity": 0.0,
        "input_phonemes": [],
        "target_phonemes": [],
        "phoneme_score": 0.0,
        "mismatches": [],
        "notes": [],
        "accepted": false,
        "score": 0.0,
        "phoneme_analysis": {}
    }

    if normalized_target.is_empty():
        evaluation["notes"].append("Brak wzorca do porównania.")
        return evaluation

    if normalized_input.is_empty():
        evaluation["notes"].append("Nie rozpoznano wypowiedzi.")
        return evaluation

    evaluation["text_distance"] = levenshtein_distance(folded_input, folded_target)
    var max_len := max(1, max(folded_input.length(), folded_target.length()))
    var text_similarity := 1.0 - float(evaluation["text_distance"]) / float(max_len)
    evaluation["text_similarity"] = clamp(text_similarity, 0.0, 1.0)

    var target_phonemes := get_phonemes_for_text(normalized_target)
    var input_phonemes := get_phonemes_for_text(normalized_input)
    evaluation["target_phonemes"] = target_phonemes
    evaluation["input_phonemes"] = input_phonemes

    var allowed_substitutions := _resolve_allowed_substitutions(context.get("allowed_substitutions", {}))
    var phoneme_analysis := _analyze_phonemes(target_phonemes, input_phonemes, allowed_substitutions, context)
    evaluation["phoneme_analysis"] = phoneme_analysis
    evaluation["phoneme_score"] = phoneme_analysis.get("score", 0.0)
    evaluation["mismatches"] = phoneme_analysis.get("mismatches", [])
    evaluation["notes"].append_array(phoneme_analysis.get("notes", []))

    var base_score := (evaluation["text_similarity"] + evaluation["phoneme_score"]) * 0.5
    var min_text_ratio := context.get("min_text_ratio", 0.65)
    var min_phoneme_score := context.get("min_phoneme_score", 0.55)
    var max_hard_errors := context.get("max_hard_errors", 2)

    var accepted := evaluation["text_similarity"] >= min_text_ratio and evaluation["phoneme_score"] >= min_phoneme_score and phoneme_analysis.get("hard_errors", 0) <= max_hard_errors
    if not accepted and phoneme_analysis.get("only_substitutions", false) and evaluation["text_similarity"] >= min_text_ratio - 0.1:
        accepted = true
        base_score = max(base_score, 0.6)
        evaluation["notes"].append("Wynik zaakceptowano dzięki tolerowanym substytucjom.")

    evaluation["accepted"] = accepted
    evaluation["score"] = base_score

    if evaluation["text_similarity"] < min_text_ratio:
        evaluation["notes"].append("Niska zgodność tekstowa (%d%%)." % int(round(evaluation["text_similarity"] * 100.0)))
    if evaluation["phoneme_score"] < min_phoneme_score:
        evaluation["notes"].append("Niska zgodność fonemiczna (%d%%)." % int(round(evaluation["phoneme_score"] * 100.0)))

    return evaluation

func get_phonemes_for_text(text: String) -> Array[String]:
    var sequence: Array[String] = []
    var processed := text.to_lower()
    var index := 0
    while index < processed.length():
        var matched := false
        var current_char := processed.substr(index, 1)
        if current_char == " ":
            index += 1
            continue
        for length in range(3, 0, -1):
            if index + length > processed.length():
                continue
            var slice := processed.substr(index, length)
            if length > 1 and _digraph_map.has(slice):
                _append_phoneme_sequence(sequence, _digraph_map[slice])
                index += length
                matched = true
                break
        if matched:
            continue
        if _grapheme_map.has(current_char):
            _append_phoneme_sequence(sequence, _grapheme_map[current_char])
        index += 1
    return sequence

func levenshtein_distance(a: String, b: String) -> int:
    var len_a := a.length()
    var len_b := b.length()
    var prev_row := []
    for i in range(len_b + 1):
        prev_row.append(i)
    for i in range(1, len_a + 1):
        var current_row := [i]
        var char_a := a.substr(i - 1, 1)
        for j in range(1, len_b + 1):
            var cost := char_a == b.substr(j - 1, 1) ? 0 : 1
            var insertion := current_row[j - 1] + 1
            var deletion := prev_row[j] + 1
            var substitution := prev_row[j - 1] + cost
            current_row.append(min(insertion, deletion, substitution))
        prev_row = current_row
    return prev_row.back()

func _append_phoneme_sequence(sequence: Array[String], data) -> void:
    if typeof(data) == TYPE_STRING:
        sequence.append(data)
    elif typeof(data) == TYPE_ARRAY:
        for element in data:
            _append_phoneme_sequence(sequence, element)

func _to_array(value) -> Array:
    if typeof(value) == TYPE_ARRAY:
        return value.duplicate()
    if typeof(value) == TYPE_PACKED_STRING_ARRAY:
        return value.duplicate()
    if value == null:
        return []
    return [value]

func _resolve_allowed_substitutions(custom: Dictionary) -> Dictionary:
    var resolved: Dictionary = {}
    for key in _substitution_map.keys():
        var values := _substitution_map[key]
        resolved[key] = values.duplicate()
    for key in custom.keys():
        var custom_values = _to_array(custom[key])
        if not resolved.has(key):
            resolved[key] = []
        for value in custom_values:
            if not resolved[key].has(value):
                resolved[key].append(value)
    return resolved

func _analyze_phonemes(target: Array[String], observed: Array[String], allowed: Dictionary, context: Dictionary) -> Dictionary:
    var result := {
        "score": 0.0,
        "mismatches": [],
        "hard_errors": 0,
        "only_substitutions": true,
        "notes": []
    }

    if target.is_empty():
        return result

    var key_weights := _resolve_key_weights(context.get("key_phonemes", []), target)
    var total_weight := 0.0
    var matched_weight := 0.0
    var length := max(target.size(), observed.size())

    for index in range(length):
        var expected := index < target.size() ? target[index] : "∅"
        var heard := index < observed.size() ? observed[index] : "∅"
        var weight := key_weights.get(expected, 1.0)
        total_weight += weight

        if expected == heard:
            matched_weight += weight
            continue

        if expected == "∅" or heard == "∅":
            result["hard_errors"] += 1
            result["mismatches"].append({
                "index": index,
                "expected": expected,
                "observed": heard,
                "type": "omission"
            })
            result["only_substitutions"] = false
            continue

        if _is_allowed_substitution(expected, heard, allowed):
            matched_weight += weight * 0.7
            result["mismatches"].append({
                "index": index,
                "expected": expected,
                "observed": heard,
                "type": "substitution"
            })
        else:
            result["hard_errors"] += 1
            result["mismatches"].append({
                "index": index,
                "expected": expected,
                "observed": heard,
                "type": "mismatch"
            })
            result["only_substitutions"] = false

    if total_weight > 0.0:
        result["score"] = matched_weight / total_weight

    if result["hard_errors"] > 0:
        result["notes"].append("%d twardych niezgodności fonemów." % result["hard_errors"])
    elif not result["mismatches"].is_empty():
        result["notes"].append("Wystąpiły jedynie dopuszczalne substytucje fonemiczne.")

    result["target"] = target
    result["observed"] = observed

    return result

func _resolve_key_weights(entries, target: Array[String]) -> Dictionary:
    var weights: Dictionary = {}
    var processed_entries: Array = []
    if typeof(entries) == TYPE_ARRAY:
        processed_entries = entries
    elif typeof(entries) == TYPE_PACKED_STRING_ARRAY:
        processed_entries = entries.duplicate()

    for entry in processed_entries:
        var phonemes: Array[String] = []
        if typeof(entry) == TYPE_STRING:
            phonemes = get_phonemes_for_text(entry)
            if phonemes.is_empty():
                phonemes = [entry]
        elif typeof(entry) == TYPE_ARRAY:
            for inner in entry:
                phonemes.append_array(get_phonemes_for_text(String(inner)))
        for phoneme in phonemes:
            var weight := max(_key_weight_map.get(phoneme, 1.4), 1.2)
            weights[phoneme] = max(weights.get(phoneme, 1.0), weight)

    if processed_entries.is_empty():
        for phoneme in target:
            if _key_weight_map.has(phoneme):
                weights[phoneme] = _key_weight_map[phoneme]

    return weights

func _is_allowed_substitution(expected: String, heard: String, allowed: Dictionary) -> bool:
    if expected == heard:
        return true
    if allowed.has(expected) and allowed[expected].has(heard):
        return true
    if allowed.has(heard) and allowed[heard].has(expected):
        return true
    return false

func _load_database(path: String) -> Dictionary:
    if not ResourceLoader.exists(path):
        push_warning("Brak pliku z bazą fonemów: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("Nie udało się otworzyć pliku fonemów: %s" % path)
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("Niepoprawny format bazy fonemów: %s" % path)
        return {}
    return parsed
