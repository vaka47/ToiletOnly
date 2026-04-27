import SwiftUI

struct AgeFilterView: View {
    @Binding var filter: AgeFilter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Фильтр ленты", "Feed filter"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.ink)

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("Возраст", "Age"))
                            .font(.headline)
                        sliderRow(
                            title: L10n.text("От \(filter.minAge)", "From \(filter.minAge)"),
                            value: Binding(
                                get: { Double(filter.minAge) },
                                set: { newValue in
                                    let value = min(Int(newValue), filter.maxAge - 1)
                                    filter.minAge = max(18, value)
                                }
                            ),
                            range: 18...60
                        )
                        sliderRow(
                            title: L10n.text("До \(filter.maxAge)", "To \(filter.maxAge)"),
                            value: Binding(
                                get: { Double(filter.maxAge) },
                                set: { newValue in
                                    let value = max(Int(newValue), filter.minAge + 1)
                                    filter.maxAge = min(60, value)
                                }
                            ),
                            range: 19...60
                        )
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("Кого показывать", "Show me"))
                            .font(.headline)
                        Picker("gender", selection: $filter.targetGender) {
                            Text(L10n.text("Все", "Anyone")).tag("any")
                            Text(L10n.text("Мужчины", "Men")).tag("male")
                            Text(L10n.text("Женщины", "Women")).tag("female")
                            Text(L10n.text("Другое", "Other")).tag("other")
                        }
                        .pickerStyle(.segmented)

                        Toggle(isOn: $filter.showNearby) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.text("Приоритет по гео", "Prioritize nearby"))
                                    .font(.headline)
                                Text(L10n.text("Онлайн-профили рядом будут выше.", "Nearby online profiles will rank higher."))
                                    .font(.caption)
                                    .foregroundColor(AppTheme.muted)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: AppTheme.coral))

                        if filter.showNearby {
                            sliderRow(
                                title: L10n.text("Радиус \(Int(filter.radiusKm)) км", "Radius \(Int(filter.radiusKm)) km"),
                                value: $filter.radiusKm,
                                range: 1...200
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AppBackground().ignoresSafeArea())
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Slider(value: value, in: range, step: 1)
                .tint(AppTheme.coral)
        }
    }
}
