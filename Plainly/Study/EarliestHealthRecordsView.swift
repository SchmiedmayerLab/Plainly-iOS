//
// This source file is part of the Plainly iOS open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveViews
import SwiftUI


struct EarliestHealthRecordsView: View {
    let dataSource: [String: Date]

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("\n\(Text("HEALTH_RECORDS_SINCE_DISCLAIMER"))")) {
                    ForEach(dataSource.keys.sorted(), id: \.self) { resourceType in
                        if let date = dataSource[resourceType] {
                            HStack {
                                Text(resourceType)
                                    .font(.headline)

                                Spacer()

                                Text(date, format: .plainlyOldestHealthSample)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("HEALTH_RECORDS_SINCE")
            .toolbar {
                ToolbarItem {
                    DismissButton()
                }
            }
        }
    }
}


extension FormatStyle where Self == Date.FormatStyle {
    static var plainlyOldestHealthSample: Date.FormatStyle {
        Self(date: .abbreviated, time: .omitted)
    }
}
