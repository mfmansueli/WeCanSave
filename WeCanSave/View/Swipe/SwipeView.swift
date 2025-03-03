//
//  SwipeView.swift
//  WeCanSave
//
//  Created by Mathew Blanc on 26/02/25.
//

import SwiftUI

struct SwipeView: View {
    
    @State var itemList: [Item]
    
    var body: some View {
        ZStack {
            ForEach(0..<itemList.count, id: \.self) { index in
                ItemView(item: itemList[index]) {
                    withAnimation {
                        removeItem(at: index)
                    }
                }
                .stacked(at: index, in: itemList.count)
            }
        }
    }
    
    func removeItem(at index: Int) {
        itemList.remove(at: index)
    }
}

extension View {
    func stacked(at position: Int, in total: Int) -> some View {
        let offset = Double(total - position)
        return self.offset(x: offset * Double.random(in: -5...5), y: offset * Double.random(in: -5...5))
    }
}

#Preview {
    SwipeView(itemList: Bag.exampleBag.itemList)
}
