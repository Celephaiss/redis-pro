//
//  RedisClient.swift
//  redis-pro
//
//  Created by chengpanwang on 2021/4/13.
//

import Foundation
import NIO
import RediStack
import Logging
import PromiseKit

class RediStackClient{
    var redisModel:RedisModel
    var connection:RedisConnection?
    var globalContext:GlobalContext?
    
    let logger = Logger(label: "redis-client")
    
    init(redisModel:RedisModel) {
        self.redisModel = redisModel
    }
    
    func setUp(_ globalContext:GlobalContext) -> Void {
        self.globalContext = globalContext
    }
    
    func pageKeys(page:Page) throws -> [RedisKeyModel] {
        do {
            logger.info("redis keys page scan, page: \(page)")
            
            let match = page.keywords.isEmpty ? nil : page.keywords
            
            var keys:[String] = [String]()
            var cursor:Int = page.cursor
            
            let res:(cursor:Int, keys:[String]) = try scan(cursor:cursor, keywords: match, count: page.size)
            
            keys.append(contentsOf: res.1)
            
            cursor = res.0
            
            // 如果取出数量不够 page.size, 继续迭带补满
            if cursor != 0 && keys.count < page.size {
                while true {
                    let moreRes:(cursor:Int, keys:[String]) = try scan(cursor:cursor, keywords: match, count: 1)
                    
                    keys.append(contentsOf: moreRes.1)
                    
                    cursor = moreRes.0
                    if cursor == 0 || keys.count == page.size {
                        break
                    }
                }
            }
            
            let total = try dbsize()
            page.total = total
            page.hasNext = cursor != 0
            page.cursor = cursor
            
            return try toRedisKeyModels(keys: keys)
        } catch {
            logger.error("query redis key page error \(error)")
            throw error
        }
    }
    
    func toRedisKeyModels(keys:[String]) throws -> [RedisKeyModel] {
        if keys.isEmpty {
            return [RedisKeyModel]()
        }
        
        var redisKeyModels:[RedisKeyModel] = [RedisKeyModel]()
        
        do {
            
            for key in keys {
                redisKeyModels.append(RedisKeyModel(key: key, type: try type(key: key)))
            }
            
            return redisKeyModels
        } catch {
            logger.error("query redis key  type error \(error)")
            throw error
        }
    }
    
    // zset operator
    func pageZSet(_ redisKeyModel:RedisKeyModel, page:Page) throws -> [(String, Double)?] {
        if redisKeyModel.isNew {
            return [(String, Double)?]()
        }
        return try pageZSet(redisKeyModel.key, page: page)
    }
    
    func pageZSet(_ key:String, page:Page) throws -> [(String, Double)?] {
        do {
            logger.info("redis set page, key: \(key), page: \(page)")
            
            let match = page.keywords.isEmpty ? nil : page.keywords
            
            var set:[(String, Double)?] = [(String, Double)?]()
            var cursor:Int = page.cursor
            
            let res:(Int, [(String, Double)?]) = try zscan(key, cursor: cursor, count: page.size, keywords: match)
            
            cursor = res.0
            
            set = res.1
            
            // 如果取出数量不够 page.size, 继续迭带补满
            if cursor != 0 && set.count < page.size {
                while true {
                    let moreRes:(Int, [(String, Double)?]) = try zscan(key, cursor:cursor, count: 1, keywords: match)
                    
                    set.append(contentsOf: moreRes.1)
                    cursor = moreRes.0
                    page.cursor = cursor
                    if cursor == 0 || set.count == page.size {
                        break
                    }
                }
            }
            
            let total = try getConnection().zcard(of: RedisKey(key)).wait()
            page.total = total
            page.hasNext = cursor != 0
            page.cursor = cursor
            
            return set
            
        } catch {
            logger.error("query redis set page error \(error)")
            throw error
        }
    }
    
    func zscan(_ key:String, cursor:Int, count:Int? = 1, keywords:String?) throws -> (Int, [(String, Double)?]) {
        do {
            logger.debug("redis set scan, key: \(key) cursor: \(cursor), keywords: \(String(describing: keywords)), count:\(String(describing: count))")
            
            return try getConnection().zscan(RedisKey(key), startingFrom: cursor, matching: keywords, count: count, valueType: String.self).wait()
            
        } catch {
            logger.error("redis set scan key:\(key) error: \(error)")
            throw error
        }
    }
    
    func zupdate(_ key:String, from:String, to:String, score:Double) throws -> Bool {
        logger.info("update zset element key: \(key), from:\(from), to:\(to), score:\(score)")
        let _ = try zrem(key, ele: from)
        return try zadd(key, score: score, ele: to)
    }
    
    func zadd(_ key:String, score:Double, ele:String) throws -> Bool {
        return try getConnection().zadd((element: ele, score: score), to: RedisKey(key)).wait()
    }
    
    func zrem(_ key:String, ele:String) throws -> Int {
        return try getConnection().zrem(ele, from: RedisKey(key)).wait()
    }
    
    // set operator
    func pageSet(_ redisKeyModel:RedisKeyModel, page:Page) throws -> [String?] {
        if redisKeyModel.isNew {
            return [String?]()
        }
        return try pageSet(redisKeyModel.key, page: page)
    }
    
    func pageSet(_ key:String, page:Page) throws -> [String?] {
        do {
            logger.info("redis set page, key: \(key), page: \(page)")
            
            let match = page.keywords.isEmpty ? nil : page.keywords
            
            var set:[String?] = [String?]()
            var cursor:Int = page.cursor
            
            let res:(Int, [String?]) = try sscan(key, cursor: cursor, count: page.size, keywords: match)
            
            cursor = res.0
            
            set = res.1
            
            // 如果取出数量不够 page.size, 继续迭带补满
            if cursor != 0 && set.count < page.size {
                while true {
                    let moreRes:(Int, [String?]) = try sscan(key, cursor:cursor, count: 1, keywords: match)
                    
                    set.append(contentsOf: moreRes.1)
                    cursor = moreRes.0
                    page.cursor = cursor
                    if cursor == 0 || set.count == page.size {
                        break
                    }
                }
            }
            
            let total = try getConnection().scard(of: RedisKey(key)).wait()
            page.total = total
            page.hasNext = cursor != 0
            page.cursor = cursor
            
            return set
            
        } catch {
            logger.error("query redis set page error \(error)")
            throw error
        }
    }
    
    func sscan(_ key:String, cursor:Int, count:Int? = 1, keywords:String?) throws -> (Int, [String?]) {
        do {
            logger.debug("redis set scan, key: \(key) cursor: \(cursor), keywords: \(String(describing: keywords)), count:\(String(describing: count))")
            
            return try getConnection().sscan(RedisKey(key), startingFrom: cursor, matching: keywords, count: count, valueType: String.self).wait()
            
        } catch {
            logger.error("redis set scan key:\(key) error: \(error)")
            throw error
        }
    }
    
    func srem(_ key:String, ele:String) throws -> Int {
        return try getConnection().srem(ele, from: RedisKey(key)).wait()
    }
    
    func supdate(_ key:String, from:String, to:String) throws -> Int {
        var r = try srem(key, ele: from)
        r += try sadd(key, ele: to)
        return r
    }
    func sadd(_ key:String, ele:String) throws -> Int {
        return try getConnection().sadd(ele, to: RedisKey(key)).wait()
    }
    
    // list operator
    
    func pageList(_ redisKeyModel:RedisKeyModel, page:Page) throws -> [String?] {
        if redisKeyModel.isNew {
            return [String?]()
        }
        return try pageList(redisKeyModel.key, page: page)
    }
    
    func pageList(_ key:String, page:Page) throws -> [String?] {
        
        do {
            logger.info("redis list page, key: \(key), page: \(page)")
            
            let cursor:Int = (page.current - 1) * page.size
            
            let total = try llen(key)
            page.total = total
            
            return try lrange(key, start: cursor, stop: cursor + page.size - 1)
            
        } catch {
            logger.error("query redis list page error \(error)")
            throw error
        }
    }
    
    func lrange(_ key:String, start:Int, stop:Int) throws -> [String?] {
        do {
            logger.debug("redis list range, key: \(key)")
            
            return try getConnection().lrange(from: RedisKey(key), firstIndex: start, lastIndex: stop, as: String.self).wait()
            
        } catch {
            logger.error("redis list range key:\(key) error: \(error)")
            throw error
        }
    }
    
    
    func lrem(_ key:String, value:String) throws -> Int {
        do {
            logger.debug("redis list lrem, key: \(key)")
            
            return try getConnection().lrem(value, from: RedisKey(key), count: 1).wait()
            
        } catch {
            logger.error("redis list lrem key:\(key) error: \(error)")
            throw error
        }
    }
    
    
    func ldel(_ key:String, index:Int) throws -> Int {
        do {
            logger.debug("redis list delete, key: \(key), index:\(index)")
            
            try lset(key, index: index, value: Constants.LIST_VALUE_DELETE_MARK)
            
            return try getConnection().lrem(Constants.LIST_VALUE_DELETE_MARK, from: RedisKey(key), count: 0).wait()
            
        } catch {
            logger.error("redis list lrem key:\(key) error: \(error)")
            throw error
        }
    }
    
    func lset(_ key:String, index:Int, value:String) throws -> Void {
        try getConnection().lset(index: index, to: value, in: RedisKey(key)).wait()
    }
    
    func lpush(_ key:String, value:String) throws -> Int {
        return try getConnection().lpush(value, into: RedisKey(key)).wait()
    }
    
    func rpush(_ key:String, value:String) throws -> Int {
        return try getConnection().rpush(value, into: RedisKey(key)).wait()
    }
    
    func llen(_ key:String) throws -> Int {
        do {
            logger.debug("redis list length, key: \(key)")
            
            return try getConnection().llen(of: RedisKey(key)).wait()
            
        } catch {
            logger.error("redis list length key:\(key) error: \(error)")
            throw error
        }
    }
    
    
    // hash operator
    
    func pageHash(_ redisKeyModel:RedisKeyModel, page:Page) throws -> [String:String?] {
        if redisKeyModel.isNew {
            return [String:String?]()
        }
        
        return try pageHash(redisKeyModel.key, page: page)
    }
    
    func pageHash(_ key:String, page:Page) throws -> [String:String?] {
        do {
            logger.info("redis hash field page scan, key: \(key), page: \(page)")
            
            let match = page.keywords.isEmpty ? nil : page.keywords
            
            var entries:[String:String?] = [String:String?]()
            var cursor:Int = page.cursor
            
            let res:(Int, [String:String?]) = try hscan(key, cursor: cursor, count: page.size, keywords: match)
            
            cursor = res.0
            
            entries = res.1
            
            // 如果取出数量不够 page.size, 继续迭带补满
            if cursor != 0 && entries.count < page.size {
                while true {
                    let moreRes:(cursor:Int, [String:String?]) = try hscan(key, cursor:cursor, count: 1, keywords: match)
                    
                    entries = entries.merging(moreRes.1) { (first, _) -> String? in
                        first
                    }
                    
                    cursor = moreRes.0
                    page.cursor = cursor
                    if cursor == 0 || entries.count == page.size {
                        break
                    }
                }
            }
            
            let total = try hlen(key)
            page.total = total
            page.hasNext = cursor != 0
            page.cursor = cursor
            
            return entries
        } catch {
            logger.error("query redis hash entry page error \(error)")
            throw error
        }
    }
    
    func hset(_ key:String, field:String, value:String) throws -> Bool {
        logger.info("redis hash hset key:\(key), field:\(field), value:\(value)")
        return try getConnection().hset(field, to: value, in: RedisKey(key)).wait()
    }
    
    func hdel(_ key:String, field:String) throws -> Int {
        logger.info("redis hash hdel key:\(key), field:\(field)")
        return try getConnection().hdel(field, from: RedisKey(key)).wait()
    }
    
    func hlen(_ key:String) throws -> Int {
        return try getConnection().hlen(of: RedisKey(key)).wait()
    }
    
    func hscan(_ key:String, cursor:Int, count:Int? = 1, keywords:String?) throws -> (Int, [String: String?]) {
        do {
            logger.debug("redis hash scan, key: \(key) cursor: \(cursor), keywords: \(String(describing: keywords)), count:\(String(describing: count))")
            
            return try getConnection().hscan(RedisKey(key), startingFrom: cursor, matching: keywords, count: count, valueType: String.self).wait()
            
        } catch {
            logger.error("redis hash scan key:\(key) error: \(error)")
            throw error
        }
    }
    
    func hget(_ key:String, field:String) throws -> String {
        do {
            let v = try getConnection().hget(field, from: RedisKey(key)).wait()
            logger.info("hget value key: \(key), field: \(field) complete, r: \(v)")
            
            if v.isNull {
                throw BizError(message: "Key `\(key)`, field: `\(field)` is not exist!")
            }
            return v.string!
        } catch {
            logger.error("get value key:\(key) error: \(error)")
            throw error
        }
    }
    
    // string operator
    
    func set(_ key:String, value:String, ex:Int?) throws -> Void {
        logger.info("set value, key:\(key), value:\(value), ex:\(ex ?? -1)")
        if (ex == nil || ex! == -1) {
            try getConnection().set(RedisKey(key), to: value).wait()
        } else {
            try getConnection().setex(RedisKey(key), to: value, expirationInSeconds: ex!).wait()
        }
    }
    
    func get(key:String) throws -> String {
        do {
            let v = try getConnection().get(RedisKey(key)).wait()
            logger.info("get value key: \(key) complete, r: \(v)")
            
            if v.isNull {
                throw BizError(message: "Key `\(key)` is not exist!")
            }
            return v.string!
        } catch {
            logger.error("get value key:\(key) error: \(error)")
            throw error
        }
    }
    
    
    func del(key:String) throws -> Int {
        do {
            let count:Int = try getConnection().delete(RedisKey(key)).wait()
            logger.info("delete redis key \(key) complete, r: \(count)")
            return count
        } catch {
            logger.error("delete redis key:\(key) error: \(error)")
            throw error
        }
    }
    
    
    
    func expire(_ key:String, seconds:Int) throws -> Bool {
        logger.info("set key expire key:\(key), seconds:\(seconds)")
        if seconds < 0 {
            let _ = try getConnection().send(command: "PERSIST", with: [RESPValue(from: key)]).wait()
            return  true
        } else {
            return try getConnection().expire(RedisKey(key), after: TimeAmount.seconds(Int64(seconds))).wait()
        }
    }
    
    func ttl(_ redisKeyModel:RedisKeyModel) throws -> Void {
        if redisKeyModel.isNew {
            return
        }
        try redisKeyModel.ttl = ttl(key: redisKeyModel.key)
    }
    
    
    func ttl(key:String) throws -> Int {
        let r:RedisKey.Lifetime = try getConnection().ttl(RedisKey(key)).wait()
        
        logger.info("query redis key ttl, key: \(key), r:\(r)")
        if r == RedisKey.Lifetime.keyDoesNotExist {
            throw BizError(message: "redis key: \(key) does not exist!")
        } else if r == RedisKey.Lifetime.unlimited {
            return -1
        } else {
            return Int(r.timeAmount!.nanoseconds / 1000000000)
        }
    }
    
    func type(key:String) throws -> String {
        do {
            let res:RESPValue = try getConnection().send(command: "type", with: [RESPValue.init(from: key)]).wait()
            
            return res.string!
        } catch {
            logger.error("query redis key  type error \(error)")
            throw error
        }
    }
    
    func scan(cursor:Int, keywords:String?, count:Int? = 1) throws -> (cursor:Int, keys:[String]) {
        do {
            logger.debug("redis keys scan, cursor: \(cursor), keywords: \(String(describing: keywords)), count:\(String(describing: count))")
            
            return try getConnection().scan(startingFrom: cursor, matching: keywords, count: count).wait()
        } catch {
            logger.error("redis keys scan error \(error)")
            throw error
        }
    }
    
    func rename(_ oldKey:String, newKey:String) throws -> Bool {
        let res:RESPValue = try getConnection().send(command: "RENAME", with: [RESPValue(from: oldKey), RESPValue(from: newKey)]).wait()
        logger.info("rename key, old key:\(oldKey), new key: \(newKey)")
        return res.string == "OK"
    }
    
    func selectDB(_ database: Int) throws -> Void {
        try getConnection().select(database: database).wait()
        logger.info("select redis database: \(database)")
    }
    
    func databases() throws -> Int {
        let res:RESPValue = try getConnection().send(command: "CONFIG", with: [RESPValue(from: "GET"), RESPValue(from: "databases")]).wait()
        let dbs = res.array
        logger.info("get config databases: \(String(describing: dbs))")
        
        return NumberHelper.toInt(dbs?[1], defaultValue: 16)
    }
    
    func dbsize() throws -> Int {
        do {
            let res:RESPValue = try getConnection().send(command: "dbsize").wait()
            
            logger.info("query redis dbsize success: \(res.int!)")
            return res.int!
        } catch {
            logger.info("query redis dbsize error: \(error)")
            throw error
        }
    }
    
    func pingAsync() -> Promise<Bool> {
        self.redisModel.loading = true
        
        
        let promise = self.getConnectionAsync()
            .then({ connection in
                Promise<Bool> { resolver in
                    connection.ping()
                        .whenComplete({completion in
                            if case .success(let pong) = completion {
                                resolver.fulfill("PONG".caseInsensitiveCompare(pong) == .orderedSame)
                            }
                            else if case .failure(let error) = completion {
                                resolver.reject(error)
                            }
                        })
                }
            })
        
        promise
            .get({ pong in
                DispatchQueue.main.async {
                    self.redisModel.ping = pong
                }
            })
            .catch({ error in
                self.logger.info("promise reject ....")
                self.globalContext?.showError(error)
            })
            .finally {
                self.logger.info("ping finally exec...")
                DispatchQueue.main.async {
                    self.redisModel.loading = false
                }
            }
        
        return promise
    }
    
    func ping() throws -> Bool {
        do {
            let pong = try getConnection().ping().wait()
            
            logger.info("ping redis server: \(pong)")
            
            if ("PONG".caseInsensitiveCompare(pong) == .orderedSame) {
                redisModel.ping = true
                return true
            }
            
            redisModel.ping = false
            return false
        } catch {
            redisModel.ping = false
            logger.error("ping redis server error \(error)")
            throw error
        }
    }
    
    func getConnectionAsync() -> Promise<RedisConnection> {
        return Promise<RedisConnection>{ resolver in
            if self.connection != nil {
                self.logger.debug("get redis exist connection...")
                resolver.fulfill(self.connection!)
            }
            
            self.logger.debug("start get new redis connection...")
            let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
            var configuration: RedisConnection.Configuration
            do {
                if (self.redisModel.password.isEmpty) {
                    configuration = try RedisConnection.Configuration(hostname: self.redisModel.host, port: self.redisModel.port, initialDatabase: self.redisModel.database)
                } else {
                    configuration = try RedisConnection.Configuration(hostname: self.redisModel.host, port: self.redisModel.port, password: self.redisModel.password, initialDatabase: self.redisModel.database)
                }
                
                
                let future = RedisConnection.make(
                    configuration: configuration
                    , boundEventLoop: eventLoop
                )
                
                future.whenSuccess({ redisConnection in
                    self.connection = redisConnection
                    resolver.fulfill(redisConnection)
                    self.logger.info("get new redis connection success")
                })
                future.whenFailure({ error in
                    self.logger.info("get new redis connection error: \(error)")
                    
                    DispatchQueue.main.async {
                        self.globalContext?.showError(error)
                    }
                    
                    resolver.reject(error)
                })
                
            } catch {
                self.logger.error("get new redis connection error \(error)")
                self.globalContext?.showError(error)
                resolver.reject(error)
            }
        }
    }
    
    func getConnection() throws -> RedisConnection{
        if self.connection != nil {
            logger.debug("get redis exist connection...")
            return self.connection!
        }
        
        logger.debug("start get new redis connection...")
        let eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        var configuration: RedisConnection.Configuration
        do {
            if (self.redisModel.password.isEmpty) {
                configuration = try RedisConnection.Configuration(hostname: self.redisModel.host, port: self.redisModel.port, initialDatabase: self.redisModel.database)
            } else {
                configuration = try RedisConnection.Configuration(hostname: self.redisModel.host, port: self.redisModel.port, password: self.redisModel.password, initialDatabase: self.redisModel.database)
            }
            
            self.connection = try RedisConnection.make(
                configuration: configuration
                , boundEventLoop: eventLoop
            ).wait()
            
            self.logger.info("get new redis connection success")
            
        } catch {
            self.logger.error("get new redis connection error \(error)")
            throw error
        }
        
        return self.connection!
    }
    
    func close() -> Void {
        do {
            if connection == nil {
                logger.info("close redis connection, connection is nil, over...")
                return
            }
            
            try connection!.close().wait()
            connection = nil
            logger.info("redis connection close success")
            
        } catch {
            logger.error("redis connection close error: \(error)")
        }
    }
}
