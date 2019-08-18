//
//  Constants.swift
//  SpotIAP
//
//  Created by Shawn Clovie on 30/1/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot

public enum IAPTransactionState: String {
	case idle
	case purchasing
	case validating
	case shouldValidate
	case validated
	case invalided
}

public struct IAPErrorSource {
	public static let productFetchFailed = AttributedError.Source("iap.productFetchFailed")
	public static let invalidReceipt = AttributedError.Source("iap.invalidReceipt")
	public static let purchaseFailed = AttributedError.Source("iap.purchaseFailed")
	public static let purchaseDeferred = AttributedError.Source("iap.purchaseDeferred")
	public static let receiptFetchFailed = AttributedError.Source("iap.receiptFetchFailed")
}
