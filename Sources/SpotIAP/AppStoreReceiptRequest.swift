//
//  AppStoreReceiptRequest.swift
//  SpotIAP iOS
//
//  Created by Shawn Clovie on 14/3/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import StoreKit
import Spot

final class AppStoreReceiptRequest: NSObject, SKRequestDelegate {
	static func loadReceiptData() throws -> Data {
		guard let url = Bundle.main.appStoreReceiptURL else {
			throw AttributedError(IAPErrorSource.receiptFetchFailed)
		}
		return try Data(contentsOf: url)
	}
	
	var completions: [(AttributedResult<Data>)->Void] = []
	
	func start() {
		let request = SKReceiptRefreshRequest(receiptProperties: nil)
		request.delegate = self
		request.start()
	}
	
	func requestDidFinish(_ request: SKRequest) {
		do {
			let data = try AppStoreReceiptRequest.loadReceiptData()
			didFinish(.success(data))
		} catch {
			didFinish(.failure(.init(with: error)))
		}
	}
	
	func request(_ request: SKRequest, didFailWithError error: Error) {
		didFinish(.failure(.init(with: error)))
	}
	
	func add(completion: @escaping (AttributedResult<Data>)->Void) {
		completions.append(completion)
	}
	
	func didFinish(_ result: AttributedResult<Data>) {
		completions.forEach{$0(result)}
		completions.removeAll()
	}
}
