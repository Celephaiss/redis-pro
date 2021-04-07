//
//  StringEditView.swift
//  redis-pro
//
//  Created by chengpanwang on 2021/4/7.
//

import SwiftUI

struct StringEditView: View {
    @State private var fullText: String = "This is some editable text..."
    
    var body: some View {
        TextEditor(text: $fullText)
            .font(/*@START_MENU_TOKEN@*/.body/*@END_MENU_TOKEN@*/)
            .multilineTextAlignment(.leading)
            .padding(0)
            .lineSpacing(1.5)
            .disableAutocorrection(true)
            .textFieldStyle(RoundedBorderTextFieldStyle())
    }
}

struct StringEditView_Previews: PreviewProvider {
    static var previews: some View {
        StringEditView()
    }
}
