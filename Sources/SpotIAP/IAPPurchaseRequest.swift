//
//  IAPPurchaseRequest.swift
//  Spot iOS
//
//  Created by Shawn Clovie on 14/3/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot

public final class IAPPurchaseRequest {
	
	public var productID: String {
		payment.productID
	}
	
	public var type: IAPProductType {
		payment.type
	}
	
	public var payment: IAPPayment
	public let provider: IAPProvider
	public let validator: IAPValidator
	
	public var discount: IAPPaymentDiscount?
	
	var purchased: (()->Void)?
	var completion: ((AttributedError?)->Void)?

	public convenience init(productID: String, of prodType: IAPProductType,
							userInfo: [AnyHashable: Any] = [:],
							by provider: IAPProvider,
							_ validator: IAPValidator) {
		let payment = IAPPayment(with: .init(providerName: provider.providerName, productID: productID), type: prodType, userInfo: userInfo)
		self.init(with: payment, by: provider, validator: validator)
	}
	
	public init(with payment: IAPPayment, by provider: IAPProvider, validator: IAPValidator) {
		self.payment = payment
		self.provider = provider
		self.validator = validator
		provider.setTransactionInfo(self)
	}
	
	public var state: IAPTransactionState {
		return IAPManager.shared.transactionState(productID: productID, by: provider)
	}
	
	public func start(purchased: (()->Void)? = nil, completion: @escaping (AttributedError?)->Void) {
		self.purchased = purchased
		self.completion = completion
		IAPManager.shared.start(request: self)
	}
	
	public func didPurchase(_ pay: IAPPayment) {
		payment.purchaseTime = pay.purchaseTime
		payment.transactionID = pay.transactionID
		if let fn = purchased {
			fn()
			purchased = nil
		}
	}
	
	public func didFinish(error: AttributedError?) {
		if let fn = completion {
			DispatchQueue.main.spot.async(error, fn)
			completion = nil
		}
	}
}
