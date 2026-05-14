//
//  AppIntent.swift
//  FridayWidget
//
//  Created by Ved Panse on 5/13/26.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Friday Focus" }
    static var description: IntentDescription { "Choose how Friday should frame your next best step." }

    @Parameter(title: "Focus Style", default: .balanced)
    var focusStyle: FridayWidgetFocusStyle
}

enum FridayWidgetFocusStyle: String, AppEnum {
    case balanced = "Balanced"
    case study = "Study"
    case work = "Work"
    case calm = "Calm"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Focus Style")

    static var caseDisplayRepresentations: [FridayWidgetFocusStyle: DisplayRepresentation] = [
        .balanced: "Balanced",
        .study: "Study",
        .work: "Work",
        .calm: "Calm",
    ]
}
