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

            WindowSettingsTab()
                .tabItem {
                    Label(L("tab_window"), systemImage: "macwindow")
                }

            HistorySettingsTab()
                .tabItem {
                    Label(L("tab_history"), systemImage: "clock")
                }

            SessionSettingsTab()
                .tabItem {
                    Label(L("tab_session"), systemImage: "arrow.clockwise")
                }
        }
        .frame(width: 450, height: 380)
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

/// ウィンドウ設定タブ
struct WindowSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_window_size")) {
                Picker(L("window_size_mode"), selection: $settings.windowSizeMode) {
                    Text(L("window_size_mode_last_used")).tag(WindowSizeMode.lastUsed)
                    Text(L("window_size_mode_fixed")).tag(WindowSizeMode.fixed)
                }
                .pickerStyle(.segmented)

                Text(L("window_size_mode_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L("section_fixed_window_size")) {
                HStack {
                    Text(L("window_width"))
                    Spacer()
                    TextField("", value: $settings.fixedWindowWidth, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("px")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(L("window_height"))
                    Spacer()
                    TextField("", value: $settings.fixedWindowHeight, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                    Text("px")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(settings.windowSizeMode != .fixed)
            .opacity(settings.windowSizeMode == .fixed ? 1.0 : 0.5)

            Section(L("section_last_window_size")) {
                HStack {
                    Text(L("current_last_window_size"))
                    Spacer()
                    Text("\(Int(settings.lastWindowWidth)) × \(Int(settings.lastWindowHeight)) px")
                        .foregroundColor(.secondary)
                }
            }
            .disabled(settings.windowSizeMode != .lastUsed)
            .opacity(settings.windowSizeMode == .lastUsed ? 1.0 : 0.5)
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

/// セッション設定タブ
struct SessionSettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section(L("section_session")) {
                Toggle(L("enable_session_restore"), isOn: $settings.sessionRestoreEnabled)

                Text(L("session_restore_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L("section_session_advanced")) {
                HStack {
                    Text(L("concurrent_loading_limit"))
                    Spacer()
                    TextField("", value: $settings.sessionConcurrentLoadingLimit, format: .number)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
                Text(L("concurrent_loading_description"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .disabled(!settings.sessionRestoreEnabled)
            .opacity(settings.sessionRestoreEnabled ? 1.0 : 0.5)

            Section(L("section_session_management")) {
                HStack {
                    Text(L("saved_windows_count_format", sessionManager.savedSession.count))
                    Spacer()
                    Button(L("clear_session")) {
                        sessionManager.clearSession()
                    }
                    .foregroundColor(.red)
                    .disabled(sessionManager.savedSession.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
