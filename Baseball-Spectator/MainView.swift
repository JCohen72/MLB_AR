//
//  MainView.swift
//  Baseball-Spectator
//
//  Created by Joey Cohen on 5/20/20.
//  Copyright © 2020 Joey Cohen. All rights reserved.
//

import SwiftUI

struct MainView: View {
    var body: some View {
        
        NavigationView {
            HStack {
                scoreboard
                
                Spacer()
                
                importButton
            }
        }
    }
    
    var importButton: some View {
        Button(action: {
            print("import")
        }) {
            Image(systemName: "plus.square")
        }
    }
    
    var scoreboard: some View {
        Text("scoreboard")
    }
}

//struct MainView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainView()
//    }
//}
