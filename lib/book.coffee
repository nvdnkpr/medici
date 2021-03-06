mongoose = require('mongoose')
entry = require('./entry')
_  = require('underscore')

Q = require('q')
module.exports = class Book

	constructor:(name) ->
		@name = name

	entry:(memo, date=null, original_journal=null) ->
		console.log 'writing with original journal:', original_journal
		return entry.write(@, memo, date,original_journal)


	# Turn query into an object readable by MongoDB
	#
	# PARAMETERS
	#	account:	acct:subacct:subsubacct(:...)
	#	start_date:
	#	month_date:
	#	meta:
	parseQuery: (query) ->
		parsed = {}
		if (account = query.account)
			accounts = account.split(':')
			for acct,i in accounts
				parsed['account_path.' + i] = acct
			delete query.account

		if query._journal
			parsed['_journal'] = query._journal

		if query.start_date? and query.end_date?
			start_date = new Date(parseInt(query.start_date))
			end_date = new Date(parseInt(query.end_date))
			parsed['datetime'] =
				$gte:start_date
				$lte:end_date
			delete query.start_date
			delete query.end_date
		else if query.start_date?
			parsed['datetime'] =
				$gte:new Date(parseInt(query.start_date))
			delete query.start_date
		else if query.end_date?
			parsed['datetime'] =
				$lte:new Date(parseInt(query.end_date))
			delete query.end_date

		keys = _.keys(mongoose.model('Medici_Transaction').schema.paths)
		for key,val of query
			if keys.indexOf(key) >= 0
				# If it starts with a _ assume it's a reference
				###if key.substr(0, 1) is '_'
					console.log 'setting val to obj id'
					val = mongoose.Types.ObjectId(val)
					console.log 'set val to oj id'
				console.log val###
				parsed[key] = val
			else
				# Assume *_id is an OID
				if key.indexOf('_id') > 0
					val = mongoose.Types.ObjectId(val)

				parsed['meta.' + key] = val

			
		# Add the book
		parsed.book = @name
		return parsed

	balance: (query) ->
		deferred = Q.defer()
		query = @parseQuery(query)

		
		match = 
			$match:query
		group = 
			$group:
				_id:'1'
				credit:
					$sum:'$credit'
				debit:
					$sum:'$debit'
		

		mongoose.model('Medici_Transaction').aggregate match, group, (err, result) ->
			if err
				deferred.reject(err)
			else

				result = result.shift()
				total = result.credit - (result.debit)
				console.log 'got total:', total
				deferred.resolve(total)
			
		return deferred.promise
	

	ledger: (query, populate=null) ->
		deferred = Q.defer()

		query = @parseQuery(query)
		q = mongoose.model('Medici_Transaction').find(query)
		if populate
			for pop in populate
				q.populate(pop)
		q.exec (err, results) ->
			if err
				deferred.reject(err)
			else
				deferred.resolve(results)
		
		return deferred.promise

	void:(journal_id, reason) ->
		deferred = Q.defer()

		# Find the journal
		mongoose.model('Medici_Journal').findById journal_id, (err, journal) =>
			if err
				deferred.reject(err)
			else
				journal.void(@, reason).then ->
					deferred.resolve()
				, (err) ->
					deferred.reject(err)

		return deferred.promise

	listAccounts: ->
		deferred = Q.defer()

		mongoose.model('Medici_Transaction').find
			book:@name
		.distinct 'accounts', (err, results) ->
			# Make array
			if err
				deferred.reject(err)
			else
				final = []
				for result in results
					paths = result.split(':')
					prev = []
					for acct in paths
						prev.push(acct)
						final.push(prev.join(':'))
				deferred.resolve(_.uniq(final))
		return deferred.promise