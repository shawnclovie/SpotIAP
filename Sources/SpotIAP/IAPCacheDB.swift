//
//  IAPCacheDB.swift
//  Spot
//
//  Created by Shawn Clovie on 28/1/2018.
//  Copyright © 2018 Shawn Clovie. All rights reserved.
//

import Foundation
import Spot
import SpotSQLite

private let fieldProvider		= SQLiteField("provider", .text)
private let fieldProductID		= SQLiteField("product_id", .text)
private let fieldPrice			= SQLiteField("price", .text)
private let fieldPriceAmount	= SQLiteField("price_amount", .real)
private let fieldTitle			= SQLiteField("title", .text)
private let fieldDescription	= SQLiteField("description", .text)
private let fieldCurrency		= SQLiteField("currency", .text)
private let fieldCacheTime		= SQLiteField("cache_time", .real)

private let fieldProductType	= SQLiteField("type", .integer)
private let fieldUserInfo		= SQLiteField("user_info", .text)
private let fieldPurchaseTime	= SQLiteField("purchase_time", .real)
private let fieldTransactionID	= SQLiteField("tran_id", .text)
private let fieldOriginalTransactionID = SQLiteField("ori_tran_id", .text)
private let fieldExpireTime		= SQLiteField("expire_time", .real)
private let fieldTransactionState	= SQLiteField("tran_state", .integer)

private let tableProductCache = SQLiteTable(
	"product_cache", [
		fieldProvider, fieldProductID,
		fieldPrice, fieldPriceAmount,
		fieldTitle, fieldDescription,
		fieldCurrency, fieldCacheTime],
	primaryKeys: [fieldProvider, fieldProductID])
private let tablePayment = SQLiteTable(
	"payment", [
		fieldProvider, fieldProductID, fieldProductType, fieldUserInfo,
		fieldTransactionID, fieldOriginalTransactionID,
		fieldPurchaseTime,
		fieldExpireTime,
		fieldTransactionState],
	primaryKeys: [fieldProvider, fieldProductID])

final class IAPCacheDB {
	
	static let shared = IAPCacheDB()
	
	let path = URL.spot_cachesPath.appendingPathComponent("\(DNSPrefix)cache").path
	let queue = DispatchQueue(label: "\(IAPCacheDB.self)")
	
	private init() {
		sync { db in
			for table in [tableProductCache, tablePayment] {
				let ql = table.createQuery(ifNotExist: true)
				try! db.prepare(ql).execute()
			}
		}
	}
	
	func sync<T>(operation: (SQLiteDB)->T) -> T {
		let db = try! SQLiteDB(path: path)
		return queue.sync{
			operation(db)
		}
	}
	
	func loadCachedProducts(from provider: IAPProvider, productIDs: [String]) -> [IAPProduct] {
		guard productIDs.isEmpty else {
			return []
		}
		return sync { db in
			let ql = "SELECT \(tableProductCache.fields.selectStatementFields)" +
				" FROM \(tableProductCache.name)" +
				" WHERE \(fieldProvider.name)=?" +
				" AND \(fieldProductID.name) IN (" +
				SQLiteDB.sqlPlaceholder(for: productIDs) + ")"
			let params = [provider.providerName] + productIDs
			let stmt = try! db.prepare(ql)
				.query(params)
			var result: [IAPProduct] = []
			while stmt.next() {
				if let item = IAPProduct(stmt) {
					result.append(item)
				}
			}
			return result
		}
	}
	
	func save(_ product: IAPProduct) {
		sync { db in
			let ql = tableProductCache.replaceQuery
			let args = tableProductCache.replaceParameters(values: [
				fieldProvider: product.providerName,
				fieldProductID: product.productID,
				fieldPrice: product.price,
				fieldPriceAmount: product.priceAmount,
				fieldTitle: product.localizedTitle,
				fieldDescription: product.localizedDescription,
				fieldCurrency: product.currency ?? "",
				fieldCacheTime: product.cacheTime,
				])
			try! db.prepare(ql).execute(args)
		}
	}
	
	func loadPayment(from provider: IAPProvider, transactionID: String) -> IAPPayment? {
		sync { db in
			let ql = "SELECT \(tablePayment.fields.selectStatementFields) FROM `\(tablePayment.name)` WHERE `\(fieldProvider.name)`=? AND `\(fieldTransactionID.name)`=?"
			let stmt = try! db.prepare(ql)
				.query([provider.providerName, transactionID])
			if stmt.next() {
				return IAPPayment(stmt)
			}
			return nil
		}
	}
	
	func loadPayment(from provider: IAPProvider, productID: String) -> IAPPayment? {
		sync { db in
			let ql = "SELECT \(tablePayment.fields.selectStatementFields)" +
				" FROM `\(tablePayment.name)`" +
				" WHERE `\(fieldProvider.name)`=? AND `\(fieldProductID.name)`=?"
			let stmt = try! db.prepare(ql)
				.query([provider.providerName, productID])
			return parsePayments(from: stmt).first
		}
	}
	
	func loadPayments() -> [IAPPayment] {
		sync { db in
			let ql = "SELECT \(tablePayment.fields.selectStatementFields)" +
				" FROM `\(tablePayment.name)`"
			let stmt = try! db.prepare(ql).query()
			return parsePayments(from: stmt)
		}
	}
	
	func loadPayments(state: IAPTransactionState) -> [IAPPayment] {
		sync { db in
			let ql = "SELECT \(tablePayment.fields.selectStatementFields)" +
				" FROM `\(tablePayment.name)`" +
				" WHERE `\(fieldTransactionState.name)`=?"
			let stmt = try! db.prepare(ql).query([state.rawValue])
			return parsePayments(from: stmt)
		}
	}
	
	private func parsePayments(from stmt: SQLiteDB.Statement) -> [IAPPayment] {
		var items: [IAPPayment] = []
		while stmt.next() {
			if let item = IAPPayment(stmt) {
				items.append(item)
			}
		}
		return items
	}
	
	func save(_ pays: [IAPPayment]) {
		sync { db in
			let ql = tablePayment.replaceQuery
			let stmt = try! db.prepare(ql)
			for pay in pays {
				let args = tablePayment.replaceParameters(values: [
					fieldProvider: pay.providerName,
					fieldProductID: pay.productID,
					fieldProductType: pay.type.rawValue,
					fieldUserInfo: (try? String.spot(jsonObject: pay.userInfo)) ?? "",
					fieldPurchaseTime: pay.purchaseTime,
					fieldTransactionID: pay.transactionID ?? "",
					fieldOriginalTransactionID: pay.originalTransactionID ?? "",
					fieldExpireTime: pay.expireTime,
					fieldTransactionState: pay.state.rawValue,
					])
				try! stmt.execute(args)
			}
		}
	}
	
	func deletePayment(productID: String) {
		sync { db in
			let (ql, args) = tablePayment.deleteQueryParameters(where: [fieldProductID: productID])
			try! db.prepare(ql).execute(args)
		}
	}
}

extension IAPProduct {
	fileprivate init?(_ stmt: SQLiteDB.Statement) {
		guard let providerName = stmt.value(of: fieldProvider).string,
			let productID = stmt.value(of: fieldProductID).string,
			let price = stmt.value(of: fieldPrice).string else {
				return nil
		}
		self.providerName = providerName
		self.productID = productID
		self.price = price
		priceAmount = stmt.value(of: fieldPriceAmount).double ?? 0
		localizedTitle = stmt.value(of: fieldTitle).string ?? ""
		localizedDescription = stmt.value(of: fieldDescription).string ?? ""
		currency = stmt.value(of: fieldCurrency).string
		cacheTime = TimeInterval(stmt.value(of: fieldCacheTime).double ?? 0)
		native = nil
	}
}

extension IAPPayment {
	fileprivate init?(_ stmt: SQLiteDB.Statement) {
		guard let providerName = stmt.value(of: fieldProvider).string,
			let typeValue = stmt.value(of: fieldProductType).integer,
			let type = IAPProductType(rawValue: Int(typeValue)),
			let productID = stmt.value(of: fieldProductID).string,
			let purchaseTime = stmt.value(of: fieldPurchaseTime).double else {
				return nil
		}
		let userInfo: [AnyHashable: Any]
		if let value = stmt.value(of: fieldUserInfo).string,
			let dict = (try? Data(value.utf8).spot.parseJSON()) as? [AnyHashable: Any] {
			userInfo = dict
		} else {
			userInfo = [:]
		}
		self.init(with: .init(providerName: providerName, productID: productID), type: type, userInfo: userInfo)
		transactionID = stmt.value(of: fieldTransactionID).string
		originalTransactionID = stmt.value(of: fieldOriginalTransactionID).string
		self.purchaseTime = TimeInterval(purchaseTime)
		if let exTime = stmt.value(of: fieldExpireTime).double {
			expireTime = TimeInterval(exTime)
		}
		if let value = stmt.value(of: fieldTransactionState).string,
			let state = IAPTransactionState(rawValue: value) {
			self.state = state
		}
	}
}
