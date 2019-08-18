//
//  IAPValidationResponse.swift
//  Spot iOS
//
//  Created by Shawn Clovie on 26/3/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation

public struct IAPValidationResponse {
	let receiptValid: Bool
	let responseData: [AnyHashable: Any]
	
	public init(receiptValid: Bool, responseData: [AnyHashable: Any]) {
		self.receiptValid = receiptValid
		self.responseData = responseData
	}
}
