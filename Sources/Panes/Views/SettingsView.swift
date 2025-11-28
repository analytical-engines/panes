import SwiftUI

/// 設定画面
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label(L("tab_general"), systemImage: "gear")
                }

            HistorySettingsTab()
                .tabItem {
                    Label(L("tab_history"), systemImage: "clock")
                }
        }
        .frame(width: 450, height: 300)
    }
}

/// 一般設定タブ
struct GeneralSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_display")) {
                Picker(L("default_view_mode"), selection: $settings.defaultViewMode) {
                    Text(L("view_mode_single")).tag(ViewMode.single)
                    Text(L("view_mode_spread")).tag(ViewMode.spread)
                }
                .pickerStyle(.segmented)

                Picker(L("default_reading_direction"), selection: $settings.defaultReadingDirection) {
                    Text(L("reading_direction_rtl")).tag(ReadingDirection.rightToLeft)
                    Text(L("reading_direction_ltr")).tag(ReadingDirection.leftToRight)
                }
                .pickerStyle(.segmented)

                Toggle(L("show_status_bar"), isOn: $settings.defaultShowStatusBar)
            }

            Section(L("section_image_detection")) {
                HStack {
                    Text(L("landscape_threshold"))
                    Spacer()
                    TextField("", value: $settings.defaultLandscapeThreshold, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text(L("landscape_threshold_unit"))
                        .foregroundColor(.secondary)
                }
                Text(L("landscape_threshold_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// 履歴設定タブ
struct HistorySettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FileHistoryManager.self) private var historyManager

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_history_settings")) {
                HStack {
                    Text(L("max_history_count"))
                    Spacer()
                    TextField("", value: $settings.maxHistoryCount, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Text(L("history_count_unit"))
                }
                Text(L("max_history_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L("section_history_management")) {
                HStack {
                    Text(L("current_history_count_format", historyManager.history.count))
                    Spacer()
                    Button(L("clear_all")) {
                        historyManager.clearAllHistory()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
