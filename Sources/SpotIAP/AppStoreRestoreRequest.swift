//
//  AppStoreRestoreRequest.swift
//  SpotIAP iOS
//
//  Created by Shawn Clovie on 16/3/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import StoreKit
import Spot

public final class AppStoreRestoreRequest {
	
	private let completion: (AttributedResult<Set<String>>)->Void
	private(set) var restoredTransactions: [SKPaymentTransaction] = []
	
	public init(completion: @escaping (AttributedResult<Set<String>>)->Void) {
		self.completion = completion
	}
	
	public func start() {
		AppStoreProvider.shared.start(request: self)
	}
	
	func didRestore(_ native: SKPaymentTransaction) {
		restoredTransactions.append(native)
	}
	
	private var restoredProductIDs: Set<String> {
		var ids: Set<String> = []
		for tran in restoredTransactions {
			ids.insert(tran.payment.productIdentifier)
		}
		return ids
	}
	
	func didFinish(error: Error?) {
		let result: AttributedResult = error.map{.failure(.init(with: $0, .operationFailed))} ?? .success(restoredProductIDs)
		DispatchQueue.main.spot.async(result, completion)
	}
}
