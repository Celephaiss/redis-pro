//
//  FormItemSecure.swift
//  redis-pro
//
//  Created by chengpanwang on 2021/7/22.
//

import SwiftUI

struct FormItemSecure: View {
    var label: String
    var labelWidth:CGFloat = 80
    var required:Bool = false
    @Binding var value: String
    
    var body: some View {
        HStack(alignment: .center) {
            if !label.isEmpty {
                FormLabel(label: label, width: labelWidth, required: required)
            }
            //            MNSTextField(text: $value)
            //            MSecureField(value: $value)/Users/chengpan/work/dream/redis-pro/redis-pro/Views/Components/FormItemTextArea.swift
//            MPasswordField(value: $value)
            NPasswordField(value: $value)
        }
    }
}

struct FormItemSecure_Previews: PreviewProvider {
    @State static var v: String = "";
    static var previews: some View {
        FormItemSecure(label: "aaa", value: $v)
    }
}
