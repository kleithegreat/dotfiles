pragma Singleton
import QtQuick
import QtCore
import Quickshell.Io

QtObject {
    id: root

    // ── Animation tree metadata (Hyprland animation hierarchy) ──
    // Each entry: { name, parent, depth, styles, category }
    readonly property var animTree: [
        { name: "global", parent: "", depth: 0, styles: [], category: "Global" },

        { name: "windows", parent: "global", depth: 1, styles: [], category: "Windows & Layers" },
        { name: "windowsIn", parent: "windows", depth: 2, styles: ["slide", "popin"], category: "Windows & Layers" },
        { name: "windowsOut", parent: "windows", depth: 2, styles: ["slide", "popin"], category: "Windows & Layers" },
        { name: "windowsMove", parent: "windows", depth: 2, styles: [], category: "Windows & Layers" },
        { name: "layers", parent: "global", depth: 1, styles: [], category: "Windows & Layers" },
        { name: "layersIn", parent: "layers", depth: 2, styles: ["slide", "popin", "fade"], category: "Windows & Layers" },
        { name: "layersOut", parent: "layers", depth: 2, styles: ["slide", "popin", "fade"], category: "Windows & Layers" },

        { name: "fade", parent: "global", depth: 1, styles: [], category: "Fading" },
        { name: "fadeIn", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeOut", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeSwitch", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeShadow", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeDim", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeGlow", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeLayers", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadeLayersIn", parent: "fadeLayers", depth: 3, styles: [], category: "Fading" },
        { name: "fadeLayersOut", parent: "fadeLayers", depth: 3, styles: [], category: "Fading" },
        { name: "fadePopups", parent: "fade", depth: 2, styles: [], category: "Fading" },
        { name: "fadePopupsIn", parent: "fadePopups", depth: 3, styles: [], category: "Fading" },
        { name: "fadePopupsOut", parent: "fadePopups", depth: 3, styles: [], category: "Fading" },
        { name: "fadeDpms", parent: "fade", depth: 2, styles: [], category: "Fading" },

        { name: "border", parent: "global", depth: 1, styles: [], category: "Other" },
        { name: "borderangle", parent: "border", depth: 2, styles: ["loop", "once"], category: "Other" },

        { name: "workspaces", parent: "global", depth: 1, styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], category: "Workspaces" },
        { name: "workspacesIn", parent: "workspaces", depth: 2, styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], category: "Workspaces" },
        { name: "workspacesOut", parent: "workspaces", depth: 2, styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], category: "Workspaces" },
        { name: "specialWorkspace", parent: "global", depth: 1, styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], category: "Workspaces" },
        { name: "specialWorkspaceIn", parent: "specialWorkspace", depth: 2, styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], category: "Workspaces" },
        { name: "specialWorkspaceOut", parent: "specialWorkspace", depth: 2, styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], category: "Workspaces" },

        { name: "zoomFactor", parent: "global", depth: 1, styles: [], category: "Other" },
        { name: "monitorAdded", parent: "global", depth: 1, styles: [], category: "Other" }
    ]

    // ── Computed lookups ──
    readonly property var _animChildren: {
        let r = {};
        for (let i = 0; i < animTree.length; i++) {
            let e = animTree[i];
            if (e.parent !== "") {
                if (!r[e.parent]) r[e.parent] = [];
                r[e.parent].push(e.name);
            }
        }
        return r;
    }

    readonly property var _animParents: {
        let r = {};
        for (let i = 0; i < animTree.length; i++) {
            let e = animTree[i];
            if (e.parent !== "") r[e.name] = e.parent;
        }
        return r;
    }

    readonly property var _animInfo: {
        let r = {};
        for (let i = 0; i < animTree.length; i++) {
            let e = animTree[i];
            r[e.name] = e;
        }
        return r;
    }

    readonly property var categories: {
        let cats = [];
        let seen = {};
        for (let i = 0; i < animTree.length; i++) {
            let c = animTree[i].category;
            if (!seen[c]) { cats.push(c); seen[c] = true; }
        }
        return cats;
    }

    readonly property var _animsByCategory: {
        let r = {};
        for (let i = 0; i < animTree.length; i++) {
            let e = animTree[i];
            if (!r[e.category]) r[e.category] = [];
            r[e.category].push(e);
        }
        return r;
    }

    // ── CSS easing presets ──
    readonly property var builtinPresets: ({
        "ease": [0.25, 0.1, 0.25, 1.0],
        "easeIn": [0.42, 0.0, 1.0, 1.0],
        "easeOut": [0.0, 0.0, 0.58, 1.0],
        "easeInOut": [0.42, 0.0, 0.58, 1.0],
        "easeInSine": [0.12, 0.0, 0.39, 0.0],
        "easeOutSine": [0.61, 1.0, 0.88, 1.0],
        "easeInOutSine": [0.37, 0.0, 0.63, 1.0],
        "easeInQuad": [0.11, 0.0, 0.5, 0.0],
        "easeOutQuad": [0.5, 1.0, 0.89, 1.0],
        "easeInOutQuad": [0.45, 0.0, 0.55, 1.0],
        "easeInCubic": [0.32, 0.0, 0.67, 0.0],
        "easeOutCubic": [0.33, 1.0, 0.68, 1.0],
        "easeInOutCubic": [0.65, 0.0, 0.35, 1.0],
        "easeInExpo": [0.7, 0.0, 0.84, 0.0],
        "easeOutExpo": [0.16, 1.0, 0.3, 1.0],
        "easeInOutExpo": [0.87, 0.0, 0.13, 1.0],
        "easeInBack": [0.36, 0.0, 0.66, -0.56],
        "easeOutBack": [0.34, 1.56, 0.64, 1.0],
        "easeInOutBack": [0.68, -0.6, 0.32, 1.6]
    })

    // ── Live state from IPC ──
    property var animations: ({})       // name -> { overridden, enabled, speed, curve, style }
    property var bezierCurves: ({})     // name -> [x1, y1, x2, y2]
    property var userCurves: ({})       // name -> [x1, y1, x2, y2] (persisted)

    // ── Keybind state ──
    property var keybinds: []           // Array of bind objects from hyprctl binds -j
    property bool keybindsLoading: false

    // ── Keybind originals (for persistence) ──
    // index -> { modmask, key } — tracks the pre-override state of changed binds.
    // Remapped to fresh indices on every refetch (see _remapKeybindState).
    property var keybindOriginals: ({})

    // ── Animation session dirty tracking ──
    // hyprctl reports base-config animation lines as overridden, so the raw
    // snapshot flag cannot drive Save/Clear; track session edits by name.
    property var animationsTouched: ({})
    // Whether non-empty override files exist on disk (probed on refresh()).
    property bool hasPersistedOverrides: false

    property bool loading: false
    property string error: ""
    property bool saving: false

    // ── Undo / redo ──
    property var _undoStack: []
    property var _redoStack: []
    readonly property bool canUndo: _undoStack.length > 0
    readonly property bool canRedo: _redoStack.length > 0

    // ── Command queue ──
    property var _commandQueue: []

    // ── User curves path ──
    readonly property string _userCurvesPath: {
        let cfg = StandardPaths.writableLocation(StandardPaths.ConfigLocation);
        if (cfg !== "")
            return cfg + "/quickshell/user_curves.json";
        return StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.config/quickshell/user_curves.json";
    }

    // ── Public API ──

    function refresh() {
        if (_fetchProc.running)
            return;
        loading = true;
        error = "";
        _fetchProc.buf = "";
        _fetchProc.running = true;
        _persistedProbeProc.running = true;
    }

    function fetchKeybinds() {
        if (_fetchBindsProc.running) return;
        keybindsLoading = true;
        _fetchBindsProc.buf = "";
        _fetchBindsProc.running = true;
    }

    function getAnimInfo(name) {
        return _animInfo[name] || null;
    }

    function animsForCategory(category) {
        return _animsByCategory[category] || [];
    }

    function hasChildren(name) {
        let children = _animChildren[name];
        return children !== undefined && children.length > 0;
    }

    function childrenInCategory(name, category) {
        let children = _animChildren[name] || [];
        let result = [];
        for (let i = 0; i < children.length; i++) {
            let info = _animInfo[children[i]];
            if (info && info.category === category)
                result.push(children[i]);
        }
        return result;
    }

    function getEffective(name) {
        let current = name;
        while (current) {
            let anim = animations[current];
            if (anim && anim.overridden)
                return { enabled: anim.enabled, speed: anim.speed, curve: anim.curve, style: anim.style };
            current = _animParents[current] || "";
        }
        return { enabled: true, speed: 8.0, curve: "default", style: "" };
    }

    function setAnimationField(name, field, value) {
        let eff = getEffective(name);
        let oldState = { enabled: eff.enabled, speed: eff.speed, curve: eff.curve, style: eff.style };
        let newState = { enabled: eff.enabled, speed: eff.speed, curve: eff.curve, style: eff.style };
        newState[field] = value;
        _pushUndo({ type: "animation", name: name, oldState: oldState, newState: newState });
        _applyAnimationState(name, newState);
    }

    function overrideAnimation(name) {
        let eff = getEffective(name);
        _applyAnimationState(name, eff);
    }

    function resetAnimation(name) {
        let parentName = _animParents[name] || "";
        if (parentName === "") return;
        _markAnimationTouched(name);
        let parentEff = getEffective(parentName);

        // Apply parent's values via IPC so the live state is correct
        let parts = [name];
        parts.push(parentEff.enabled ? "1" : "0");
        parts.push(String(parentEff.speed));
        parts.push(parentEff.curve || "default");
        if (parentEff.style) parts.push(parentEff.style);
        let animCmd = "keyword animation " + parts.join(", ");
        let curve = parentEff.curve || "default";
        let curvePoints = getCurvePoints(curve);
        let batch = [];
        if (curve !== "default" && curve !== "linear" && curvePoints)
            batch.push("keyword bezier " + curve + ", " + curvePoints.join(", "));
        batch.push(animCmd);
        _queueCommand(batch);

        // Mark as not overridden locally so UI shows "inherited"
        // and saveAll() won't include this animation
        let nextAnims = _cloneObj(animations);
        delete nextAnims[name];
        animations = nextAnims;
    }

    // ── Curve management ──

    function getAllCurveNames() {
        let names = [];
        let seen = {};
        function addSorted(obj) {
            let keys = Object.keys(obj); keys.sort();
            for (let i = 0; i < keys.length; i++) {
                if (!seen[keys[i]]) { names.push(keys[i]); seen[keys[i]] = true; }
            }
        }
        addSorted(userCurves);
        addSorted(bezierCurves);
        addSorted(builtinPresets);
        return names;
    }

    function getCurvePoints(name) {
        if (userCurves[name]) return userCurves[name];
        if (bezierCurves[name]) return bezierCurves[name];
        if (builtinPresets[name]) return builtinPresets[name];
        return null;
    }

    function isUserCurve(name) {
        return userCurves[name] !== undefined;
    }

    function saveUserCurve(name, points) {
        let next = _cloneObj(userCurves);
        next[name] = [points[0], points[1], points[2], points[3]];
        userCurves = next;
        _persistUserCurves();
    }

    function deleteUserCurve(name) {
        let next = _cloneObj(userCurves);
        delete next[name];
        userCurves = next;
        _persistUserCurves();
    }

    function renameUserCurve(oldName, newName) {
        if (!userCurves[oldName]) return;
        let next = _cloneObj(userCurves);
        next[newName] = next[oldName];
        delete next[oldName];
        userCurves = next;
        _persistUserCurves();
    }

    function nextCustomName() {
        let existing = userCurves;
        let i = 1;
        while (existing["custom" + i]) i++;
        return "custom" + i;
    }

    // ── Persistence ──

    readonly property bool hasAnimationOverrides: Object.keys(animationsTouched).length > 0

    readonly property bool hasKeybindOverrides: {
        let originals = keybindOriginals;
        let indices = Object.keys(originals);
        let binds = keybinds;
        for (let i = 0; i < indices.length; i++) {
            let idx = parseInt(indices[i]);
            let bind = binds[idx];
            if (!bind) continue;
            let orig = originals[indices[i]];
            if (bind.modmask !== orig.modmask || bind.key !== orig.key)
                return true;
        }
        return false;
    }

    function saveAll() {
        if (saving) return;
        saving = true;
        _saveAnimations();
        _saveKeybinds();
    }

    function clearAll() {
        if (saving) return;
        saving = true;
        _clearAnimationsProc.running = true;
    }

    function _resetAfterClear() {
        animations = ({});
        animationsTouched = ({});
        keybindOriginals = ({});
        _undoStack = [];
        _redoStack = [];
        refresh();
        fetchKeybinds();
    }

    function _markAnimationTouched(name) {
        let next = _cloneObj(animationsTouched);
        next[name] = true;
        animationsTouched = next;
    }

    function _saveAnimations() {
        let anims = animations;
        let payload = { beziers: {}, animations: [] };

        let keys = Object.keys(anims);
        for (let i = 0; i < keys.length; i++) {
            let a = anims[keys[i]];
            if (!a.overridden) continue;

            let curve = a.curve || "default";
            // Include the curve control points if it's a named curve
            if (curve !== "default" && curve !== "linear") {
                let pts = getCurvePoints(curve);
                if (pts) payload.beziers[curve] = [pts[0], pts[1], pts[2], pts[3]];
            }

            payload.animations.push({
                name: keys[i],
                enabled: a.enabled,
                speed: a.speed,
                curve: curve,
                style: a.style || ""
            });
        }

        _saveAnimationsProc.command = ["desktopctl", "hypr", "animations", "save",
                                        JSON.stringify(payload)];
        _saveAnimationsProc.running = true;
    }

    function _saveKeybinds() {
        let originals = keybindOriginals;
        let indices = Object.keys(originals);
        if (indices.length === 0) return;

        let payload = { overrides: [] };
        for (let i = 0; i < indices.length; i++) {
            let idx = parseInt(indices[i]);
            let bind = keybinds[idx];
            if (!bind) continue;
            let orig = originals[indices[i]];

            // Skip no-op overrides (current matches original)
            if (bind.modmask === orig.modmask && bind.key === orig.key)
                continue;

            payload.overrides.push({
                original_mods: _modmaskToString(orig.modmask),
                original_key: orig.key,
                new_mods: _modmaskToString(bind.modmask),
                new_key: bind.key,
                flags: _buildBindFlags(bind),
                description: bind.description || "",
                dispatcher: bind.dispatcher,
                arg: bind.arg !== undefined ? bind.arg : ""
            });
        }

        if (payload.overrides.length === 0) return;

        _saveKeybindsProc.command = ["desktopctl", "hypr", "keybinds", "save",
                                      JSON.stringify(payload)];
        _saveKeybindsProc.running = true;
    }

    // ── Undo / redo ──

    function undo() {
        if (_undoStack.length === 0) return;
        let stack = _undoStack.slice();
        let entry = stack.pop();
        _undoStack = stack;
        let redo = _redoStack.slice();
        redo.push(entry);
        _redoStack = redo;
        if (entry.type === "animation")
            _applyAnimationState(entry.name, entry.oldState);
        else if (entry.type === "monitor")
            monitorUndoRequested(entry.name, entry.oldState);
        else if (entry.type === "bind")
            _applyBindSwitch(parseInt(entry.name), entry.newState, entry.oldState);
    }

    function redo() {
        if (_redoStack.length === 0) return;
        let stack = _redoStack.slice();
        let entry = stack.pop();
        _redoStack = stack;
        let undo = _undoStack.slice();
        undo.push(entry);
        _undoStack = undo;
        if (entry.type === "animation")
            _applyAnimationState(entry.name, entry.newState);
        else if (entry.type === "monitor")
            monitorUndoRequested(entry.name, entry.newState);
        else if (entry.type === "bind")
            _applyBindSwitch(parseInt(entry.name), entry.oldState, entry.newState);
    }

    // Signal emitted when a monitor undo/redo needs to be applied.
    // The display pane listens to this and calls DisplayService.applyMonitorConfig.
    signal monitorUndoRequested(string monitorName, var state)

    function pushMonitorUndo(monitorName, oldState, newState) {
        _pushUndo({ type: "monitor", name: monitorName, oldState: _cloneObj(oldState), newState: _cloneObj(newState) });
    }

    // ── Key-capture submap session ──
    // Owned by the singleton so the submap teardown (and its safety timeout)
    // survives destruction of the settings pane that started the capture.

    property bool captureSessionActive: false

    signal captureSessionReady()

    function beginCaptureSession() {
        captureSessionActive = true;
        _captureSafetyTimer.restart();
        _captureSetupProc.running = true;
    }

    function endCaptureSession() {
        captureSessionActive = false;
        _captureSafetyTimer.stop();
        _captureResetProc.running = true;
    }

    property Timer _captureSafetyTimer: Timer {
        interval: 10000
        onTriggered: {
            if (root.captureSessionActive)
                root.endCaptureSession();
        }
    }

    // ── Keybind override ──

    function applyBindOverride(bindIndex, newModNames, newKey) {
        let binds = keybinds.slice();
        let bind = binds[bindIndex];
        if (!bind) return;

        let oldModmask = bind.modmask;
        let oldKey = bind.key;
        let newModmask = _modsToMask(newModNames);

        // Track the original state for persistence (first change wins)
        let originals = _cloneObj(keybindOriginals);
        if (originals[bindIndex] === undefined)
            originals[bindIndex] = { modmask: oldModmask, key: oldKey };
        keybindOriginals = originals;

        _pushUndo({
            type: "bind", name: String(bindIndex),
            oldState: _cloneObj({ modmask: oldModmask, key: oldKey }),
            newState: _cloneObj({ modmask: newModmask, key: newKey })
        });

        let updated = _cloneObj(bind);
        updated.modmask = newModmask;
        updated.key = newKey;
        binds[bindIndex] = updated;
        keybinds = binds;

        _queueCommand(_buildBindBatch(bind, oldModmask, oldKey, newModmask, newKey));
    }

    function _applyBindSwitch(bindIndex, fromState, toState) {
        let binds = keybinds.slice();
        let bind = binds[bindIndex];
        if (!bind) return;

        let updated = _cloneObj(bind);
        updated.modmask = toState.modmask;
        updated.key = toState.key;
        binds[bindIndex] = updated;
        keybinds = binds;

        _queueCommand(_buildBindBatch(updated, fromState.modmask, fromState.key,
                                       toState.modmask, toState.key));
    }

    function _buildBindBatch(bind, oldModmask, oldKey, newModmask, newKey) {
        let oldModStr = _modmaskToString(oldModmask);
        let newModStr = _modmaskToString(newModmask);
        let batch = ["keyword unbind " + oldModStr + ", " + oldKey];
        let flags = _buildBindFlags(bind);
        let parts = [newModStr, newKey];
        if (bind.has_description) parts.push(bind.description || "");
        parts.push(bind.dispatcher);
        parts.push(bind.arg !== undefined ? bind.arg : "");
        batch.push("keyword bind" + flags + " " + parts.join(", "));
        return batch;
    }

    function _modmaskToString(mask) {
        let parts = [];
        if (mask & 64) parts.push("SUPER");
        if (mask & 4) parts.push("CTRL");
        if (mask & 8) parts.push("ALT");
        if (mask & 1) parts.push("SHIFT");
        return parts.join(" ");
    }

    function _modsToMask(mods) {
        let mask = 0;
        for (let i = 0; i < mods.length; i++) {
            if (mods[i] === "SUPER") mask |= 64;
            else if (mods[i] === "SHIFT") mask |= 1;
            else if (mods[i] === "CTRL") mask |= 4;
            else if (mods[i] === "ALT") mask |= 8;
        }
        return mask;
    }

    function _buildBindFlags(bind) {
        let f = "";
        if (bind.has_description) f += "d";
        if (bind.locked) f += "l";
        if (bind.release) f += "r";
        if (bind.repeat) f += "e";
        if (bind.mouse) f += "m";
        if (bind.non_consuming) f += "n";
        return f;
    }

    // Stable bind identity: dispatcher/arg/description/flags plus the current
    // combo (the combo disambiguates duplicate-identity binds).
    function _bindIdentityMatches(a, b) {
        return a.dispatcher === b.dispatcher
            && (a.arg !== undefined ? a.arg : "") === (b.arg !== undefined ? b.arg : "")
            && (a.description || "") === (b.description || "")
            && (a.submap || "") === (b.submap || "")
            && _buildBindFlags(a) === _buildBindFlags(b)
            && a.modmask === b.modmask
            && a.key === b.key;
    }

    // Re-key keybindOriginals from the previous local list onto a freshly
    // fetched list: overrides reorder the bind list (unbind + append), so
    // index-keyed tracking goes stale on every refetch. Index-keyed bind
    // undo/redo entries cannot be trusted across a refetch either; drop them.
    function _remapKeybindState(newBinds) {
        let oldBinds = keybinds;
        let originals = keybindOriginals;
        let indices = Object.keys(originals);
        let nextOriginals = {};
        let used = {};
        for (let i = 0; i < indices.length; i++) {
            let oldBind = oldBinds[parseInt(indices[i])];
            if (!oldBind) continue;
            for (let j = 0; j < newBinds.length; j++) {
                if (used[j]) continue;
                if (_bindIdentityMatches(oldBind, newBinds[j])) {
                    nextOriginals[j] = originals[indices[i]];
                    used[j] = true;
                    break;
                }
            }
        }
        keybindOriginals = nextOriginals;
        _undoStack = _undoStack.filter((entry) => entry.type !== "bind");
        _redoStack = _redoStack.filter((entry) => entry.type !== "bind");
    }

    // ── Internal helpers ──

    function _cloneObj(obj) {
        return JSON.parse(JSON.stringify(obj || {}));
    }

    function _pushUndo(entry) {
        let stack = _undoStack.slice();
        if (stack.length > 0) {
            let top = stack[stack.length - 1];
            if (top.type === entry.type && top.name === entry.name
                    && (entry.type === "animation" || entry.type === "monitor" || entry.type === "bind")) {
                stack[stack.length - 1] = {
                    type: entry.type, name: entry.name,
                    oldState: top.oldState, newState: entry.newState
                };
                _undoStack = stack;
                _redoStack = [];
                return;
            }
        }
        stack.push(entry);
        if (stack.length > 100) stack.shift();
        _undoStack = stack;
        _redoStack = [];
    }

    function _applyAnimationState(name, state) {
        _markAnimationTouched(name);
        let nextAnims = _cloneObj(animations);
        nextAnims[name] = {
            overridden: true,
            enabled: state.enabled,
            speed: state.speed,
            curve: state.curve || "default",
            style: state.style || ""
        };
        animations = nextAnims;

        let parts = [name];
        parts.push(state.enabled ? "1" : "0");
        parts.push(String(state.speed));
        parts.push(state.curve || "default");
        if (state.style) parts.push(state.style);
        let animCmd = "keyword animation " + parts.join(", ");

        let curve = state.curve || "default";
        let curvePoints = getCurvePoints(curve);
        let batch = [];
        if (curve !== "default" && curve !== "linear" && curvePoints)
            batch.push("keyword bezier " + curve + ", " + curvePoints.join(", "));
        batch.push(animCmd);
        _queueCommand(batch);
    }

    function _queueCommand(batch) {
        let q = _commandQueue.slice();
        q.push(batch);
        _commandQueue = q;
        _drainQueue();
    }

    function _drainQueue() {
        if (_keywordProc.running || _commandQueue.length === 0)
            return;
        let q = _commandQueue.slice();
        let batch = q.shift();
        _commandQueue = q;
        _keywordProc.command = batch.length === 1
            ? ["hyprctl", batch[0]]
            : ["hyprctl", "--batch", batch.join(" ; ")];
        _keywordProc.running = true;
    }

    function _parseAnimationsResponse(buf) {
        try {
            let data = JSON.parse(buf);
            if (!Array.isArray(data) || data.length < 2) return;

            let nextAnims = {};
            for (let i = 0; i < data[0].length; i++) {
                let a = data[0][i];
                if (a.name.indexOf("__") === 0) continue;
                nextAnims[a.name] = {
                    overridden: a.overridden,
                    enabled: a.enabled,
                    speed: a.speed,
                    curve: a.bezier || "",
                    style: a.style || ""
                };
            }
            animations = nextAnims;

            let nextCurves = {};
            for (let i = 0; i < data[1].length; i++) {
                let c = data[1][i];
                nextCurves[c.name] = [c.X0, c.Y0, c.X1, c.Y1];
            }
            bezierCurves = nextCurves;
        } catch (e) {
            error = "Failed to parse animation data";
            console.log("[HyprlandConfigService] parse error:", e);
        }
    }

    function _persistUserCurves() {
        let json = JSON.stringify(userCurves, null, 2);
        _saveCurvesProc.command = [
            "bash", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1.tmp\" && mv \"$1.tmp\" \"$1\"",
            "_", _userCurvesPath, json
        ];
        _saveCurvesProc.running = true;
    }

    // ── Processes ──

    property Process _fetchProc: Process {
        command: ["hyprctl", "animations", "-j"]
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { _fetchProc.buf += line + "\n"; } }
        onExited: (code) => {
            if (code === 0 && _fetchProc.buf.trim() !== "")
                root._parseAnimationsResponse(_fetchProc.buf);
            else if (code !== 0)
                root.error = "Failed to fetch animation state";
            _fetchProc.buf = "";
            root.loading = false;
        }
    }

    property Process _keywordProc: Process {
        running: false
        stdout: SplitParser { onRead: (_) => {} }
        stderr: SplitParser {
            onRead: (line) => { console.log("[HyprlandConfigService] hyprctl stderr:", line); }
        }
        onExited: (code) => {
            if (code !== 0)
                root.error = "Failed to apply Hyprland setting";
            root._drainQueue();
        }
    }

    property Process _saveCurvesProc: Process {
        running: false
        stderr: SplitParser {
            onRead: (line) => { console.log("[HyprlandConfigService] save curves error:", line); }
        }
    }

    property Process _loadCurvesProc: Process {
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { _loadCurvesProc.buf += line + "\n"; } }
        onExited: (code) => {
            if (code === 0 && _loadCurvesProc.buf.trim() !== "") {
                try {
                    root.userCurves = JSON.parse(_loadCurvesProc.buf);
                } catch (e) {
                    console.log("[HyprlandConfigService] user curves parse error:", e);
                }
            }
            _loadCurvesProc.buf = "";
        }
    }

    property Process _captureSetupProc: Process {
        command: ["hyprctl", "--batch",
            "keyword submap hyprmod_capture ; keyword bind , catchall, pass, ; keyword submap reset"]
        running: false
        stdout: SplitParser { onRead: (_) => {} }
        onExited: (code) => {
            if (code === 0 && root.captureSessionActive)
                _captureEnterProc.running = true;
        }
    }

    property Process _captureEnterProc: Process {
        command: ["hyprctl", "dispatch", "submap", "hyprmod_capture"]
        running: false
        stdout: SplitParser { onRead: (_) => {} }
        onExited: (code) => {
            if (code === 0 && root.captureSessionActive)
                root.captureSessionReady();
        }
    }

    // Leaves the live submap, then unbinds the capture catchall so it does
    // not accumulate in `hyprctl binds` across capture sessions.
    property Process _captureResetProc: Process {
        command: ["hyprctl", "--batch",
            "dispatch submap reset ; keyword submap hyprmod_capture ; keyword unbind , catchall ; keyword submap reset"]
        running: false
        stdout: SplitParser { onRead: (_) => {} }
    }

    property Process _fetchBindsProc: Process {
        command: ["hyprctl", "binds", "-j"]
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { _fetchBindsProc.buf += line + "\n"; } }
        onExited: (code) => {
            if (code === 0 && _fetchBindsProc.buf.trim() !== "") {
                try {
                    let parsed = JSON.parse(_fetchBindsProc.buf);
                    if (Array.isArray(parsed)) {
                        root._remapKeybindState(parsed);
                        root.keybinds = parsed;
                    }
                }
                catch (e) { console.log("[HyprlandConfigService] binds parse error:", e); }
            }
            _fetchBindsProc.buf = "";
            root.keybindsLoading = false;
        }
    }

    property Process _saveAnimationsProc: Process {
        running: false
        stderr: SplitParser {
            onRead: (line) => { console.log("[HyprlandConfigService] save animations error:", line); }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.error = "Failed to save animation overrides";
            } else {
                root.animationsTouched = ({});
                _persistedProbeProc.running = true;
            }
            if (!_saveKeybindsProc.running)
                root.saving = false;
        }
    }

    property Process _persistedProbeProc: Process {
        command: ["bash", "-c",
            "test -s ~/.config/hypr/animations-override.conf -o -s ~/.config/hypr/keybinds-override.conf"]
        running: false
        onExited: (code) => { root.hasPersistedOverrides = code === 0; }
    }

    property Process _clearAnimationsProc: Process {
        command: ["desktopctl", "hypr", "animations", "clear"]
        running: false
        stderr: SplitParser {
            onRead: (line) => { console.log("[HyprlandConfigService] clear animations error:", line); }
        }
        onExited: (code) => {
            if (code !== 0)
                root.error = "Failed to clear animation overrides";
            // Only started by clearAll(); always chain to the keybinds clear.
            _clearKeybindsProc.running = true;
        }
    }

    property Process _saveKeybindsProc: Process {
        running: false
        stderr: SplitParser {
            onRead: (line) => { console.log("[HyprlandConfigService] save keybinds error:", line); }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.error = "Failed to save keybind overrides";
            } else {
                // desktopctl runs `hyprctl reload`, which reorders the bind
                // list; refetch so index-keyed tracking is remapped. Originals
                // are kept: each save rewrites the override file wholesale, so
                // they must accumulate across saves within the session.
                root.fetchKeybinds();
                _persistedProbeProc.running = true;
            }
            if (!_saveAnimationsProc.running)
                root.saving = false;
        }
    }

    property Process _clearKeybindsProc: Process {
        command: ["desktopctl", "hypr", "keybinds", "clear"]
        running: false
        stderr: SplitParser {
            onRead: (line) => { console.log("[HyprlandConfigService] clear keybinds error:", line); }
        }
        onExited: (code) => {
            if (code !== 0)
                root.error = "Failed to clear keybind overrides";
            root.saving = false;
            root._resetAfterClear();
        }
    }

    Component.onCompleted: {
        _loadCurvesProc.command = ["cat", _userCurvesPath];
        _loadCurvesProc.running = true;
    }
}
