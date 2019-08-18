//
//  IAPPurchase.swift
//  Spot
//
//  Created by Shawn Clovie on 12/20/15.
//  Copyright © 2015 Shawn Clovie. All rights reserved.
//

import Foundation

public protocol IAPPaymentDiscount {}

public func ==(lhs: IAPPayment, rhs: IAPPayment) -> Bool {
	lhs.purchaseTime == rhs.purchaseTime && lhs.productID == rhs.productID
}

public protocol IAPNativePayment {}

/// Purchase infomation, may serialize.
public struct IAPPayment {

	public var providerName: String {
		product.providerName
	}
	
	public var productID: String {
		product.productID
	}
	
	public var product: IAPProduct
	public let type: IAPProductType
	public var userInfo: [AnyHashable: Any]
	public var applicationUsername: String?
	
	public var transactionID: String?
	public var originalTransactionID: String?
	public var purchaseTime: TimeInterval = 0
	public var expireTime: TimeInterval = 0
	
	public var native: IAPNativePayment?
	
	var state: IAPTransactionState = .idle
	
	public init(with product: IAPProduct, type: IAPProductType, userInfo: [AnyHashable: Any], native: IAPNativePayment? = nil) {
		self.product = product
		self.type = type
		self.userInfo = userInfo
		self.native = native
	}
}
