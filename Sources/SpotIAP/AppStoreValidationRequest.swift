//
//  AppStoreValidationRequest.swift
//  SpotIAP iOS
//
//  Created by Shawn Clovie on 14/3/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot

private let ReceiptStatusValid = 0
private let ReceiptStatusReadDataFailed = 21000
private let ReceiptStatusNoData = 21002
private let ReceiptStatusAuthenticateFailed = 21003
private let ReceiptStatusSharedSecretInvalid = 21004
private let ReceiptStatusServerNotAvailiable = 21005
private let ReceiptStatusTestReceiptSentToProductServer = 21007
private let ReceiptStatusProductReceiptSentToTestServer = 21008

final class AppStoreValidationRequest {
	
	/// Validate receipt, this may query receipt content information.
	///
	/// - Parameters:
	///   - sharedSecret: App's shared secret (hexadecimal). Only used for contains auto-renewable subscriptions.
	///   - excludeOldTransaction: Should include only the latest renewal transacion for any subscriptions. Only used for subscriptions.
	///   - sandbox: Is the receipt from sandbox environment.
	func start(receipt: Data, sharedSecret: String,
			   excludeOldTransaction: Bool, sandbox: Bool,
			   completion: @escaping (AttributedResult<IAPValidationResponse>)->Void) {
		var params: [AnyHashable: Any] = ["receipt-data": receipt.base64EncodedString()]
		if !sharedSecret.isEmpty {
			params["password"] = sharedSecret
		}
		if excludeOldTransaction {
			params["exclude-old-transactions"] = true
		}
		let url = URL(string: sandbox
			? "https://sandbox.itunes.apple.com/verifyReceipt"
			: "https://buy.itunes.apple.com/verifyReceipt")!
		var request = URLRequest.spot(.post, url)
		do {
			request.httpBody = try JSONSerialization.data(withJSONObject: params)
		} catch {
			DispatchQueue.main.spot.async(.failure(.init(.operationFailed, object: params, original: error)), completion)
			return
		}
		URLTask(request).request { task, result in
			switch result {
			case .failure(let err):
				completion(.failure(err))
			case .success(let data):
				let err: AttributedError
				do {
					let json = try JSONSerialization.jsonObject(with: data) as? [AnyHashable: Any] ?? [:]
					let status = json["status"] as? Int ?? ReceiptStatusReadDataFailed
					switch status {
					case ReceiptStatusValid:
						completion(.success(IAPValidationResponse(receiptValid: true, responseData: json)))
						return
					case ReceiptStatusTestReceiptSentToProductServer,
						 ReceiptStatusProductReceiptSentToTestServer:
						self.start(receipt: receipt, sharedSecret: sharedSecret, excludeOldTransaction: excludeOldTransaction, sandbox: !sandbox, completion: completion)
						return
					case ReceiptStatusSharedSecretInvalid:
						err = AttributedError(.invalidArgument, userInfo: ["message": "shared_secret_invalid"])
					case ReceiptStatusServerNotAvailiable:
						err = AttributedError(.serviceMissing)
					case ReceiptStatusAuthenticateFailed,
						 ReceiptStatusNoData,
						 ReceiptStatusReadDataFailed:
						completion(.success(IAPValidationResponse(receiptValid: false, responseData: json)))
						return
					default:
						err = AttributedError(.operationFailed, object: status)
					}
				} catch {
					err = AttributedError(.invalidFormat, original: error)
				}
				completion(.failure(err))
			}
		}
	}
}
