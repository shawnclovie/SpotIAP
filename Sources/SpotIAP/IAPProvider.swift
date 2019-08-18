//
//  IAPProvider.swift
//  Spot
//
//  Created by Shawn Clovie on 12/20/15.
//  Copyright © 2015 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot

public protocol IAPValidator: class {
	/// Validate purchase
	func validate(_ payment: IAPPayment, by provider: IAPProvider, completion: @escaping (AttributedResult<IAPValidationResponse>)->Void)
}

/// In-app Purchase Provider
public protocol IAPProvider: class {
	
	static var storeName: String {get}
	
	var canMakePayment: Bool {get}
	
	func transactionState(productID: String) -> IAPTransactionState?
	
	func setTransactionInfo(_ request: IAPPurchaseRequest)
	
	/// Purchase with request, should call IAPManager.shared.purchaseDidFinish(_:,_:)
	func purchase(_ request: IAPPurchaseRequest)
	
	/// Finish transaction, usually calling after validate finished.
	/// - Return:
	///   - nil: succcessfuly finished.
	///   - AttributedError(.itemNotFound): no transaction found in queue.
	///   - IAPError.purchaseDeferred: transaction is deferred or purchasing.
	func finishTransaction(productID: String)
	
	func purchaseDidFinish(_ request: IAPPurchaseRequest, _ response: IAPValidationResponse)
}

extension IAPProvider {
	public var providerName: String {
		NSStringFromClass(type(of: self))
	}
}
