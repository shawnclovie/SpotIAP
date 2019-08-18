//
//  IAPProduct.swift
//  Spot
//
//  Created by Shawn Clovie on 12/20/15.
//  Copyright © 2015 Shawn Clovie. All rights reserved.
//

import Foundation

public enum IAPProductType: Int {
	case consumable, nonConsumable, subscriptions
}

public protocol IAPNativeProduct {
}

/// IAP product info.
public struct IAPProduct {
	
	/// Class name of the provider
	public let providerName: String
	/// Product identify. e.g. "com.abc.def.coin1"
	public let productID: String
	public var price: String
	public var localizedTitle = ""
	public var localizedDescription = ""
	public var priceAmount: Double = 0
	public var currency: String?
	public var cacheTime: TimeInterval
	
	/// Native object. SKProduct on iOS.
	public var native: IAPNativeProduct?
	
	init(providerName: String, productID: String, price: String = "") {
		self.providerName = providerName
		self.productID = productID
		self.price = price
		cacheTime = Date().timeIntervalSince1970
	}
}
