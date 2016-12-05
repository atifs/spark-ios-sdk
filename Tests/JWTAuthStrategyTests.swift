// Copyright 2016 Cisco Systems Inc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


import Foundation
import XCTest
@testable import SparkSDK


fileprivate class MockJWTStorage: JWTAuthStorage {
    var authenticationInfo: JWTAuthenticationInfo?
}

fileprivate class MockJWTClient: JWTAuthClient {
    var fetchTokenFromJWT_callCount = 0
    var fetchTokenFromJWT_completionHandler: ObjectHandler?
    
    override func fetchTokenFromJWT(_ jwt: String, queue: DispatchQueue? = nil, completionHandler: @escaping ObjectHandler) {   
        fetchTokenFromJWT_completionHandler = completionHandler
        fetchTokenFromJWT_callCount = fetchTokenFromJWT_callCount + 1
    }
}

class JWTAuthStrategyTests: XCTestCase {
    private static let oneDay: TimeInterval = 24*60*60
    private let yesterday = Date(timeIntervalSinceNow: -OAuthStrategyTests.oneDay)
    private let tomorrow = Date(timeIntervalSinceNow: OAuthStrategyTests.oneDay)
    private let now = Date()
    private var storage: MockJWTStorage!
    private var client: MockJWTClient!
    private static let testJWT = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJibGFoIiwiaXNzIjoidGhpc0lzQVRlc3QiLCJleHAiOjQxMDI0NDQ4MDB9.p4frHZUGx8Qi60P77fl09lKCRGoJFNZzUqBm2fKOfC4"
    
    override func setUp() {
        storage = MockJWTStorage()
        client = MockJWTClient()
    }
    
    func testWhenValidAccessTokenThenItIsImmediatelyReturned() {
        let testObject = createTestObject()
        
        storage.authenticationInfo = JWTAuthenticationInfo(token: "accessToken1", tokenExpirationDate: tomorrow)
        
        var retrievedAccessToken: String? = nil
        testObject.accessToken() { accessToken in
            retrievedAccessToken = accessToken
        }
        
        XCTAssertEqual(retrievedAccessToken, "accessToken1")
        
    }
    
    func testWhenAccessTokenAndJWTAreExpiredThenNilIsImmediatelyReturnedForAccessToken() {
        let expiredTestJWT = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJibGFoIiwiaXNzIjoidGhpc0lzQVRlc3QiLCJleHAiOjE0NTE2MDY0MDB9.qgOgOrakNKAgvBumc5qwbK_ypEAVRpKi7cZWev1unSY"
        let testObject = createTestObject(jwt: expiredTestJWT)

        storage.authenticationInfo = JWTAuthenticationInfo(token: "accessToken1", tokenExpirationDate: yesterday)
        var count = 0
        var retrievedAccessToken: String? = nil
        testObject.accessToken() { accessToken in
            retrievedAccessToken = accessToken
            count = count + 1
        }
        
        XCTAssertEqual(count, 1)
        XCTAssertNil(retrievedAccessToken)
        XCTAssertEqual(client.fetchTokenFromJWT_callCount, 0)
    }
    
    func testWhenAccessTokenExpiredButJWTIsValidThenAccessTokenIsRefreshed() {
        let testObject = createTestObject()
        
        storage.authenticationInfo = JWTAuthenticationInfo(token: "accessToken1", tokenExpirationDate: yesterday)
        var count = 0
        var retrievedAccessToken: String? = nil
        testObject.accessToken() { accessToken in
            retrievedAccessToken = accessToken
            count = count + 1
        }
        XCTAssertEqual(count, 0)
        
        XCTAssertEqual(client.fetchTokenFromJWT_callCount, 1)
        
        if let completionHandler = client.fetchTokenFromJWT_completionHandler {
            let accessTokenObject = JWTAccessTokenCreationResult(token: "accessToken2")
            accessTokenObject.tokenCreationDate = now
            accessTokenObject.tokenExpiration = JWTAuthStrategyTests.oneDay
            completionHandler(ServiceResponse<JWTAccessTokenCreationResult>(nil, Result.success(accessTokenObject)))
        }
        
        XCTAssertEqual(retrievedAccessToken, "accessToken2")
        XCTAssertEqual(count, 1)
        
        let authInfo = storage.authenticationInfo
        XCTAssertEqual(authInfo?.token, "accessToken2")
        XCTAssertEqualWithAccuracy(authInfo?.tokenExpirationDate.timeIntervalSinceReferenceDate ?? 0, tomorrow.timeIntervalSinceReferenceDate, accuracy: 1.0)
    }
    
    func testWhenAccessTokenFetchFailsThenDeauthorized() {
        let testObject = createTestObject()
        
        storage.authenticationInfo = JWTAuthenticationInfo(token: "accessToken1", tokenExpirationDate: yesterday)
        var count = 0
        var retrievedAccessToken: String? = nil
        testObject.accessToken() { accessToken in
            retrievedAccessToken = accessToken
            count = count + 1
        }
        
        if let completionHandler = client.fetchTokenFromJWT_completionHandler {
            let error = NSError()
            completionHandler(ServiceResponse<JWTAccessTokenCreationResult>(nil, Result.failure(error)))
        }
        
        XCTAssertEqual(retrievedAccessToken, nil)
        XCTAssertNil(storage.authenticationInfo)
        XCTAssertEqual(count, 1)
    }
    
    func testWhenDeauthorizedThenAuthInfoIsCleared() {
        let testObject = createTestObject()
        
        storage.authenticationInfo = JWTAuthenticationInfo(token: "accessToken1", tokenExpirationDate: yesterday)
        testObject.deauthorize()
        
        XCTAssertFalse(testObject.authorized)
        XCTAssertNil(storage.authenticationInfo)
    }
    
    private func createTestObject(jwt: String = testJWT) -> JWTAuthStrategy {
        return JWTAuthStrategy(jwt: jwt, storage: storage, client: client)
    }
}