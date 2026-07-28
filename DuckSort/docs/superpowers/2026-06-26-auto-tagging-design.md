# Auto Tagging — Design Spec

## 1. Overview

Auto-tagging analyzes a photo's EXIF metadata **only when focused in the large viewer** and suggests tags based on configurable rules. The user accepts or dismisses each suggestion. No batch scanning, no persistence of dismissed suggestions, no overhead when the large viewer is closed.

## 2. Architecture

### Components

- **AutoTagEngine** (utility, `Sendable`) — pure function: `MetadataSnapshot` → `[AutoTagSuggestion]`. No I/O, fast, called on-demand when a photo is focused.
- **AutoTagSuggestionsView** — SwiftUI view rendered in:
  - Large viewer sidebar (above "ACTIVE TAGS")
  - Grid sidebar's Tags section (above categories)
- **SettingsAutoTaggingPaneView** — new tab in existing settings window with rule editor.

### Data Flow

```
Photo focused in large viewer
  → get MetadataSnapshot (already loaded)
  → AutoTagEngine(snapshot) → [AutoTagSuggestion]
  → UI renders suggestions
```

### Integration Points

- **LargeImageViewerSidebar** — insert `AutoTagSuggestionsView` above "ACTIVE TAGS" section
- **SidebarView (TagsSectionView)** — insert suggestions above categories when applicable
- **SettingsPaneWindow** — add new `.autoTagging` tab alongside Rules, Tags, Copyright, Shortcuts
- **UserPreferences** — store enabled/disabled state and custom rules

## 3. Data Model

### AutoTagSuggestion

```swift
struct AutoTagSuggestion: Identifiable, Sendable {
    let id: UUID
    let tagName: String           // e.g. "Fuji", "Wide Angle"
    let reason: String            // e.g. "Camera: Fujifilm X-T5" or "35mm eq. 24mm"
    let categoryID: UUID?         // nil = suggest new tag, not = existing category
    let confidence: Confidence    // .high, .medium, .low
}

enum Confidence: String, Codable {
    case high
    case medium
    case low
}
```

### AutoTagRule

```swift
struct AutoTagRule: Codable, Sendable {
    let id: UUID
    var name: String              // Display name in settings, e.g. "Camera Brand"
    var enabled: Bool = true      // Toggle on/off
    var condition: Condition
    var suggestedTags: [SuggestedTag]
}

enum Condition: Codable, Sendable {
    case cameraBrand(contains: String)       // "Fujifilm"
    case focalLength35mm(lessThan: Double)   // 35.0
    case focalLength35mm(moreThan: Double)   // 200.0
    case iso(lessThan: Int)                  // 100
    case iso(moreThan: Int)                  // 6400
    case aperture(lessThan: Double)          // 2.8
    case aperture(moreThan: Double)          // 8.0
    case flashFired
    case flashNotFired
    case aspectRatio(widthToHeight ratio: Double)  // 1.5 = 3:2
    case imageStabilization
    case lensType(contains: String)          // "Macro", "Telephoto"
    case lensTypeNot(contains: String)       // "Prime"
}

struct SuggestedTag: Codable, Sendable {
    let name: String    // The tag name to suggest
    let category: String?  // Optional category to create/use
}
```

### Default Shipped Rules (all enabled by default)

| Condition | Suggested Tag |
|---|---|
| Camera contains "Fujifilm" | "Fuji" |
| 35mm eq. focal length < 35mm | "Wide Angle" |
| 35mm eq. focal length > 200mm | "Telephoto" |
| ISO < 200 | "Low ISO" |
| ISO > 3200 | "High ISO" |
| Aperture < 2.8 | "Shallow Depth of Field" |
| Aperture > 8.0 | "Deep Depth of Field" |
| Flash fired | "Flash" |
| Flash did not fire | "Natural Light" |
| Aspect ratio ~1.5 | "3:2" |
| Aspect ratio ~1.78 | "16:9" |
| Lens contains "Macro" | "Macro" |
| Lens contains "Tele" | "Telephoto" |
| Lens contains "Wide" | "Wide Angle" |

Note: Users can configure lens-based rules (e.g., `lensType(contains: "24-70mm")` → suggest "Zoom") instead of using any hardcoded zoom condition.

## 4. UI Design

### Large Viewer Sidebar

Insert `AutoTagSuggestionsView` between "IMAGE METADATA" and "ACTIVE TAGS" sections:

```
┌──────────────────────────────┐
│ IMAGE METADATA               │
│ ───────────────────────────  │
│ Camera: Fujifilm X-T5        │
│ Lens: XF 24mm F1.4           │
├──────────────────────────────┤
│ SUGGESTED TAGS               │  ← NEW
│ ┌──────────────────────────┐ │
│ │ Fuji                     │ │
│ │ Camera: Fujifilm X-T5    │ │
│ │ [✓ Accept] [× Dismiss]   │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ Wide Angle               │ │
│ │ 35mm eq. 24mm            │ │
│ │ [✓ Accept] [× Dismiss]   │ │
│ └──────────────────────────┘ │
├──────────────────────────────┤
│ ACTIVE TAGS                  │
│ Fuji  Wide Angle  (applied)  │
├──────────────────────────────┤
│ IMAGE METADATA               │
│ ...                          │
└──────────────────────────────┘
```

Each suggestion card shows:
- **Tag name** (bold, prominent)
- **Reason** (smaller text, e.g. "Camera: Fujifilm X-T5")
- **Accept button** (✓) — applies the tag to the current photo (or creates it if it doesn't exist)
- **Dismiss button** (×) — hides this suggestion for the current photo view

### Grid Sidebar

In `TagsSectionView`, render a compact "Suggestions" row above categories when the current photo has suggestions:

```
┌──────────────────────────────┐
│ TAGS                         │
│ ───────────────────────────  │
│ Flags & Ratings              │
│ ───────────────────────────  │
│ SUGGESTIONS     (3)          │  ← NEW (compact row)
│ Fuji · Wide Angle · Macro    │
│ [Apply All] [× Dismiss All]  │
│ ───────────────────────────  │
│ Scene                        │
│ Fuji (2)  Wide Angle (3)     │
│ Macro (1)                    │
│ ───────────────────────────  │
│ Action                       │
│ ...                          │
└──────────────────────────────┘
```

### Settings: Auto Tagging Tab

New tab in the unified settings window:

```
┌──────────────────────────────────────┐
│ AUTO TAGGING                         │
│ Suggest tags based on EXIF metadata. │
│ Rules are applied per-photo in the   │
│ large viewer.                        │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ [✓] Camera Brand                 │ │
│ │ Fujifilm → "Fuji"                │ │
│ │                                  │ │
│ │ [✓] Focal Length < 35mm          │ │
│ │ → "Wide Angle"                   │ │
│ │                                  │ │
│ │ [✓] Focal Length > 200mm         │ │
│ │ → "Telephoto"                    │ │
│ │                                  │ │
│ │ [✓] ISO < 200                    │ │
│ │ → "Low ISO"                      │ │
│ └──────────────────────────────────┘ │
│                                      │
│ [+ Add Rule]                         │
└──────────────────────────────────────┘
```

Each rule editor supports:
- **Name** (free text)
- **Condition** (picker: Camera Brand, Focal Length, ISO, Aperture, Flash, Aspect Ratio, Lens Type, Image Stabilization)
- **Condition value** (text for brand/lens, number for ISO/focal length/aperture)
- **Suggested tag name(s)** (one or more)
- **Optional category** (dropdown of existing categories, or create new)
- **Enabled toggle**

## 5. Auto-Tag Engine Logic

`AutoTagEngine` takes a `MetadataSnapshot` and evaluates all enabled rules:

```swift
class AutoTagEngine: Sendable {
    func suggestions(from metadata: MetadataSnapshot, rules: [AutoTagRule]) -> [AutoTagSuggestion]
}
```

### Evaluation

For each enabled rule:
1. Check if the condition matches the metadata
2. If matched, create a suggestion for each `SuggestedTag`
3. Assign confidence based on certainty:
   - `.high`: exact matches (camera brand, flash fired/not fired, lens contains specific string)
   - `.medium`: ranges (ISO, aperture, focal length thresholds)
   - `.low`: approximations (aspect ratio matching)

### Dismissed Suggestions (ephemeral)

Dismissed suggestions are **ephemeral** — they are not persisted. Dismissing a suggestion hides it for the current photo view only. Navigating away and back will re-show the suggestion. This avoids unnecessary file I/O and keeps the feature lightweight.

## 6. Tag Creation on Accept

When user accepts a suggestion:
1. Check if a tag with that name already exists in the active pack
2. If yes, apply the existing tag (existing `applyTag` flow)
3. If no, offer to create it:
   - If a category is specified, create the tag in that category
   - If no category, create in a new "Auto-Tagged" category (or the user's choice)
4. Write to XMP sidecar (existing `XMPTaggingService` flow)

## 7. Settings Integration

### UserPreferences additions

```swift
@Published var autoTaggingEnabled: Bool = true
@Published var autoTaggingRules: [AutoTagRule] = defaultRules
```

### SettingsTab enum

Add `.autoTagging` to `SettingsTab` enum in `SettingsPaneWindow.swift`.

### SettingsAutoTaggingPaneView

- **Rule list view** — scrollable list of all rules with toggles
- **Rule editor** — sheet with condition picker, value input, suggested tag input
- **Presets** — section for default rules that can be individually toggled
- **Custom rules** — section for user-created rules

## 8. File Locations

| File | Purpose |
|---|---|
| `DuckSort/Models/AutoTagRule.swift` | Rule, Condition, SuggestedTag models |
| `DuckSort/Utilities/AutoTagEngine.swift` | EXIF analysis engine |
| `DuckSort/Utilities/AutoTagEngine.swift` | EXIF analysis engine |
| `DuckSort/Views/AutoTagSuggestionsView.swift` | Large viewer sidebar suggestions |
| `DuckSort/Views/SettingsAutoTaggingPaneView.swift` | Settings tab |
| `DuckSort/Models/UserPreferences.swift` | Add autoTaggingEnabled + autoTaggingRules |
| `DuckSort/Views/SettingsPaneWindow.swift` | Add .autoTagging tab |
| `DuckSort/Views/Components/LargeImageViewerSidebar.swift` | Insert suggestions |
| `DuckSort/Views/SidebarView.swift` | Insert suggestions in TagsSectionView |

## 9. Edge Cases

- **No EXIF data** — no suggestions shown
- **Missing focal length** — skip focal length rules
- **Camera model not in EXIF** — skip camera brand rules
- **Accepted tag doesn't exist** — offer to create it in existing or new category
- **Multiple suggestions for same tag** — deduplicate (same tagName + same category)
- **User creates a tag with the same name as a suggestion** — next focus, suggestion shows as already applied (grayed out with "Applied" label)

## 10. Non-Goals

- Batch scanning during library import (out of scope for v1)
- Persistence of dismissed suggestions across app relaunches (ephemeral per-session)
- Auto-applying suggestions without user confirmation
- ML-based image content analysis (EXIF only)
